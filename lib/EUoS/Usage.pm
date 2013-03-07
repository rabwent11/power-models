﻿package EUoS::Usage;

=head Copyright licence and disclaimer

Copyright 2012-2013 Franck Latrémolière, Reckon LLP and others.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY AUTHORS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

use warnings;
use strict;
use utf8;
use SpreadsheetModel::Shortcuts ':all';

sub new {
    my ( $class, $model, $setup, $customers ) = @_;
    bless { model => $model, setup => $setup, customers => $customers }, $class;
}

sub usageRates {
    my ($self) = @_;
    return $self->{usageRates} if $self->{usageRates};
    my ( $model, $setup, $customers ) = @{$self}{qw(model setup customers)};

    # given up on marking some cells out of use -- was too hardcoded
    my $allBlank = [
        map {
            [ map { '' } $customers->tariffSet->indices ]
        } $self->usageSet->indices
    ];
    push @{ $model->{usageTables} }, my @usageRates = (
        Dataset(
            name     => 'Network usage of 1kW of average consumption',
            rows     => $customers->tariffSet,
            cols     => $self->usageSet,
            number   => 1531,
            appendTo => $model->{inputTables},
            dataset  => $model->{dataset},
            data     => $allBlank,
        ),
        Dataset(
            name     => 'Network usage of an exit point',
            rows     => $customers->tariffSet,
            cols     => $self->usageSet,
            number   => 1532,
            appendTo => $model->{inputTables},
            dataset  => $model->{dataset},
            data     => $allBlank,
        ),
        Dataset(
            name     => 'Network usage of 1kVA of agreed capacity',
            rows     => $customers->tariffSet,
            cols     => $self->usageSet,
            number   => 1533,
            appendTo => $model->{inputTables},
            dataset  => $model->{dataset},
            data     => $allBlank,
        ),
    );
    $self->{usageRates} = \@usageRates;
}

sub usageSet {
    my ($self) = @_;
    $self->{usageSet} ||= Labelset(
        name => 'Network usage categories',
        list => [
            'Boundary capacity kVA',
            'Ring capacity kVA',
            'Transformer capacity kVA',
            'Low voltage network capacity kVA',
            'Metering switchgear for ring supply',
            'Low voltage metering switchgear',
            'Low voltage service 100 Amp',
            'Energy consumption kW',
        ]
    );
}

sub boundaryUsageSet {
    my ($self) = @_;
    $self->{boundaryUsageSet} ||= Labelset(
        name => 'Boundary usage',
        list => [ $self->usageSet->{list}[0] ]
    );
}

sub energyUsageSet {
    my ($self) = @_;
    my $listr = $self->usageSet->{list};
    $self->{energyUsageSet} ||= Labelset(
        name => 'Energy usage',
        list => [ $listr->[$#$listr] ]
    );
}

sub assetUsageSet {
    my ($self) = @_;
    my $listr = $self->usageSet->{list};
    $self->{assetUsageSet} ||= Labelset(
        name => 'Asset usage',
        list => [ @{$listr}[ 1 .. ( $#$listr - 1 ) ] ]
    );
}

sub totalUsage {
    my ( $self, $volumes ) = @_;
    return $self->{totalUsage}{ 0 + $volumes }
      if $self->{totalUsage}{ 0 + $volumes };
    my $labelTail =
      $volumes->[0]{usetName} ? " for $volumes->[0]{usetName}" : '';
    my $usageRates    = $self->usageRates;
    my $customerUsage = Arithmetic(
        name       => 'Network usage by customers' . $labelTail,
        rows       => $volumes->[0]{rows},
        cols       => $usageRates->[0]{cols},
        arithmetic => '=' . join(
            '+',
            map {
                my $m = $_ + 1;
                my $v = $_ + 100;
                "IV$m*IV$v" . ( $_ ? '' : '/24/IV666' );
              } 0 .. 2    # undue hardcoding (only zero is a unit rate)
        ),
        arguments => {
            IV666 => $self->{setup}->daysInYear,
            map {
                my $m = $_ + 1;
                my $v = $_ + 100;
                (
                    "IV$m" => $usageRates->[$_],
                    "IV$v" => $volumes->[$_]
                );
              } 0 .. 2    # undue hardcoding
        },
        defaultFormat => '0softnz',
    );
    $self->{totalUsage}{ 0 + $volumes } = GroupBy(
        defaultFormat => '0softnz',
        name          => 'Total network usage' . $labelTail,
        rows          => 0,
        cols          => $customerUsage->{cols},
        source        => $customerUsage,
    );
}

sub finish { }

1;
