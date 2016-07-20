﻿package Elec::Setup;

=head Copyright licence and disclaimer

Copyright 2012-2016 Franck Latrémolière, Reckon LLP and others.

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
    my ( $class, $model ) = @_;
    $model->register(  bless { model => $model }, $class);
}

sub daysInYear {
    my ($self) = @_;
    $self->{daysInYear} ||= Dataset(
        name       => 'Days in the charging year',
        validation => {
            validate => 'decimal',
            criteria => 'between',
            minimum  => 365,
            maximum  => 366,
        },
        data          => [365],
        defaultFormat => '0hard'
    );
}

sub annuityRate {
    my ($self) = @_;
    return $self->{annuityRate} if $self->{annuityRate};

    my $annuitisationPeriod = Dataset(
        name       => 'Annualisation period (years)',
        validation => {
            validate => 'decimal',
            criteria => 'between',
            minimum  => 0,
            maximum  => 999_999,
        },
        data          => [45],
        defaultFormat => '0hard',
    );

    my $rateOfReturn = Dataset(
        name       => 'Rate of return',
        validation => {
            validate      => 'decimal',
            criteria      => 'between',
            minimum       => 0,
            maximum       => 4,
            input_title   => 'Rate of return:',
            input_message => 'Percentage',
            error_message => 'The rate of return must be'
              . ' a non-negative percentage value.'
        },
        defaultFormat => '%hard',
        data          => [0.103]
    );

    $self->{annuityRate} = Arithmetic(
        name          => 'Annuity rate',
        defaultFormat => '%soft',
        arithmetic    => '=PMT(A1,A2,-1)',
        arguments     => {
            A1 => $rateOfReturn,
            A2 => $annuitisationPeriod,
        }
    );

}

sub tariffComponents {
    my ($self) = @_;
    $self->{tariffComponents} ||= [
        (
            map { "$_ p/kWh" }
              $self->{model}{timebands}
            ? @{ $self->{model}{timebands} }
            : 'Unit'
        ),
        'Fixed p/day',
        'Capacity p/kVA/day',
    ];
}

sub digitsRounding {
    my ($self) = @_;
    $self->{model}{noRounding} ? []
      : [
        (
            $self->{model}{timebands} ? map { 3 } @{ $self->{model}{timebands} }
            : 3
        ),
        0, 2,
      ];
}

sub volumeComponents {
    my ($self) = @_;
    $self->{volumeComponents} ||= [
        (
            map { "$_ kWh" }
              $self->{model}{timebands}
            ? @{ $self->{model}{timebands} }
            : 'Units'
        ),
        'Supply points',
        'Capacity kVA',
    ];
}

sub finish {
    my ($self) = @_;
    return if $self->{generalInputDataTable};
    return
      unless my @columns = (
        $self->{daysInYear} || (),
        $self->{annuityRate}
        ? @{ $self->{annuityRate}{arguments} }{qw(A1 A2)}
        : ()
      );
    $self->{generalInputDataTable} |= Columnset(
        name     => 'Financial and general input data',
        number   => 1510,
        appendTo => $self->{model}{inputTables},
        dataset  => $self->{model}{dataset},
        columns  => \@columns,
    );
}

1;
