﻿package Quantiles;

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
use Quantiles::Sheets;
use SpreadsheetModel::Quantile;

sub new {

    my $class = shift;
    my $model = bless {
        inputTables => [],
        @_
    }, $class;

    $model->{numTariffs} ||= 3;
    my $tariffSet = Labelset(
        name          => 'Tariffs',
        list          => [ 1 .. $model->{numTariffs} ],
        defaultFormat => 'thtar',
    );
    my $blank = [ map { '' } 1 .. $model->{numTariffs} ];

    my @levels =
      ( '132kV circuits', '132kV/EHV', 'EHV circuits', 'EHV/HV', '132kV/HV' );
    my @levelShortNames = qw(132 BSP EHV Pri Pri132);
    $model->{calcSheetNames} =
      [ map { [ $levelShortNames[$_] => $levels[$_] ] } 0 .. $#levels ];

    my %dnos = (
        'ENWL'          => 'Electricity North West Limited',
        'NPG Northeast' => 'Northern Powergrid Northeast',
        'NPG Yorkshire' => 'Northern Powergrid Yorkshire',
        'SPEN SPD'      => 'SP Distribution',
        'SPEN SPM'      => 'SP Manweb',
        'SSEPD SEPD'    => 'SEPD',
        'SSEPD SHEPD'   => 'SHEPD',
        'UKPN EPN'      => 'Eastern Power Networks',
        'UKPN LPN'      => 'London Power Networks',
        'UKPN SPN'      => 'South Eastern Power Networks',
        'WPD EastM'     => 'WPD East Midlands',
        'WPD SWales'    => 'WPD South Wales',
        'WPD SWest'     => 'WPD South West',
        'WPD WestM'     => 'WPD West Midlands'
    );
    my $lastNumber = 1220;

    my @dat;
    foreach my $dno ( sort keys %dnos ) {
        my @cols = map {
            Dataset(
                name    => $levels[$_],
                rows    => $tariffSet,
                data    => $blank,
                dataset => $model->{dataset},
            );
        } 0 .. $#levels;
        my $name = Dataset(
            name          => 'Tariff name',
            defaultFormat => 'texthard',
            data          => [ map { 'Not used' } 1 .. $model->{numTariffs} ],
            rows          => $tariffSet,
            dataset       => $model->{dataset}
        );
        if ( $model->{catFilter} ) {
            my $cat = Dataset(
                name          => 'Customer category',
                defaultFormat => '0000hard',
                data          => [ map { '' } 1 .. $model->{numTariffs} ],
                rows          => $tariffSet,
                dataset       => $model->{dataset}
            );
            my @c2 = (
                Arithmetic(
                    name       => $levels[0],
                    arithmetic => '=IF(IV1>999,IV2,"n/a")',
                    arguments  => { IV1 => $cat, IV2 => $cols[0], }
                ),
                Arithmetic(
                    name       => $levels[1],
                    arithmetic => '=IF(MOD(IV1,1000)>99,IV2,"n/a")',
                    arguments  => { IV1 => $cat, IV2 => $cols[1], }
                ),
                Arithmetic(
                    name       => $levels[2],
                    arithmetic => '=IF(MOD(IV1,100)>9,IV2,"n/a")',
                    arguments  => { IV1 => $cat, IV2 => $cols[2], }
                ),
                Arithmetic(
                    name => $levels[3],
                    arithmetic =>
                      '=IF(AND(MOD(IV1,10)>0,MOD(IV3,1000)>1),IV2,"n/a")',
                    arguments => { IV1 => $cat, IV3 => $cat, IV2 => $cols[3], }
                ),
                Arithmetic(
                    name       => $levels[4],
                    arithmetic => '=IF(MOD(IV1,1000)=1,IV2,"n/a")',
                    arguments  => { IV1 => $cat, IV2 => $cols[4], }
                ),
            );
            unshift @cols, $cat;
            push @{ $dat[$_] }, $c2[$_] foreach 0 .. $#levels;
            push @{ $model->{filterTables} },
              Columnset(
                name    => "$dnos{$dno} (filtered)",
                columns => [ Stack( sources => [$name] ), @c2 ]
              );
        }
        else {
            push @{ $dat[$_] }, $cols[$_] foreach 0 .. $#levels;
        }
        unshift @cols, $name;
        $model->{dnoData}{$dno} = Columnset(
            name                  => $dnos{$dno},
            columns               => \@cols,
            number                => ++$lastNumber,
            dataset               => $model->{dataset},
            location              => $dno,
            doNotCopyInputColumns => 1,
        );
        $lastNumber += 3;
    }

    my $q1 = Dataset(
        name          => 'Collar percentile',
        defaultFormat => '%hard',
        data          => [.15],
        dataset       => $model->{dataset},
        validation    => {
            validate => 'decimal',
            criteria => 'between',
            minimum  => 0,
            maximum  => 1,
        },
    );
    my $q2 = Dataset(
        name          => 'Cap percentile',
        defaultFormat => '%hard',
        data          => [.85],
        dataset       => $model->{dataset},
        validation    => {
            validate => 'decimal',
            criteria => 'between',
            minimum  => 0,
            maximum  => 1,
        },
    );
    Columnset(
        name     => 'Percentiles',
        appendTo => $model->{inputTables},
        columns  => [ $q1, $q2 ]
    );

    my ( @cap, @collar );

    foreach ( 0 .. $#levels ) {
        $collar[$_] = new SpreadsheetModel::Quantile(
            quantile       => $q1,
            toUse          => $dat[$_],
            name           => Label( $levels[$_], "$levels[$_] collar" ),
            conditionMaker => sub {
                my ($v) = @_;
                Arithmetic(
                    name       => 'Condition',
                    arithmetic => '=IF(ISNUMBER(IV1),AND(IV2>0,IV3<1))',
                    arguments  => { IV1 => $v, IV2 => $v, IV3 => $v }
                );
            },
            PERCENTILE => $model->{PERCENTILE},
        );
        $cap[$_] = new SpreadsheetModel::Quantile(
            quantile       => $q2,
            toUse          => $dat[$_],
            name           => Label( $levels[$_], "$levels[$_] cap" ),
            conditionMaker => sub {
                my ($v) = @_;
                Arithmetic(
                    name       => 'Condition',
                    arithmetic => '=IF(ISNUMBER(IV1),IV2>1)',
                    arguments  => { IV1 => $v, IV2 => $v }
                );
            },
            PERCENTILE => $model->{PERCENTILE},
        );
        push @{ $model->{calcTables}[$_] },
          values %{ $collar[$_]{arguments} },
          values %{ $cap[$_]{arguments} };
    }

    push @{ $model->{resultsTables} },
      Columnset( name => 'Collar values', columns => \@collar ),
      Columnset( name => 'Cap values',    columns => \@cap );

    $model;

}

1;