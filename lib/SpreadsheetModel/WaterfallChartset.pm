﻿package SpreadsheetModel::WaterfallChartset;

# Copyright 2017-2019 Franck Latrémolière, Reckon LLP and others.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHORS AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use warnings;
use strict;
use utf8;
use SpreadsheetModel::Shortcuts ':all';
use SpreadsheetModel::WaterfallChart;
use SpreadsheetModel::ChartSeries;

sub tablesAndCharts {

    my ( $class, $settings, $cols, $chartTitlesMaybe, ) = @_;
    my ( @tables, @charts );
    my $rows = $settings->{rows} || $cols->[0]{rows};
    my $csetName = ( $cols->[0]{location} || $cols->[0] )->objectShortName;

    # Column order:
    # 0 = final position
    # 1 = starting point
    # 2 = first step
    # 3 = second step
    # etc

    my $n         = $cols->[1]->objectShortName;
    my @value_pos = (
        Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => '=MAX(A1,0)',
            arguments  => { A1 => $cols->[1] },
        )
    );
    my @value_neg = (
        Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => '=MIN(A1,0)',
            arguments  => { A1 => $cols->[1] },
        )
    );
    my @padding = (
        Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => '=NA()',
            arguments  => { A1 => $cols->[1] },
        )
    );
    my @increase = (
        Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => '=NA()',
            arguments  => { A1 => $cols->[1] },
        )
    );
    my @decrease = (
        Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => '=NA()',
            arguments  => { A1 => $cols->[1] },
        )
    );

    for ( my $i = 2 ; $i <= @$cols ; ++$i ) {
        my $j = $i % @$cols;
        $n = $cols->[$j]->objectShortName;
        push @value_pos,
          Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => $j ? '=NA()' : '=MAX(A1,0)',
            arguments => { A1 => $cols->[$j] },
          );
        push @value_neg,
          Arithmetic(
            name       => $n,
            rows       => $rows,
            arithmetic => $j ? '=NA()' : '=MIN(A1,0)',
            arguments => { A1 => $cols->[$j] },
          );
        push @padding,
          Arithmetic(
            name => $n,
            rows => $rows,
            arithmetic =>
              '=IF(A1<0,IF(A2<0,MAX(A11,A21),0),IF(A23<0,0,MIN(A12,A22)))',
            arguments => {
                A1  => $cols->[ $i - 1 ],
                A11 => $cols->[ $i - 1 ],
                A12 => $cols->[ $i - 1 ],
                A2  => $cols->[$j],
                A21 => $cols->[$j],
                A22 => $cols->[$j],
                A23 => $cols->[$j],
            },
          );
        push @increase,
          Arithmetic(
            name => $n,
            rows => $rows,
            arithmetic =>
              '=MAX(0,MAX(A2,0)-MAX(A1,0))+MIN(0,MIN(A11,0)-MIN(A21,0))',
            arguments => {
                A1  => $cols->[ $i - 1 ],
                A11 => $cols->[ $i - 1 ],
                A21 => $cols->[$j],
                A2  => $cols->[$j],
            },
          );
        push @decrease,
          Arithmetic(
            name => $n,
            rows => $rows,
            arithmetic =>
              '=MAX(0,MAX(A1,0)-MAX(A2,0))+MIN(0,MIN(A21,0)-MIN(A11,0))',
            arguments => {
                A1  => $cols->[ $i - 1 ],
                A11 => $cols->[ $i - 1 ],
                A21 => $cols->[$j],
                A2  => $cols->[$j],
            },
          );
    }

    push @tables,
      my $valueColumnset = Columnset(
        name    => "$csetName: baseline positive values",
        columns => \@value_pos,
      );
    push @tables,
      my $valueNegColumnset = Columnset(
        name    => "$csetName: baseline negative values",
        columns => \@value_neg,
      );
    push @tables,
      my $paddingColumnset = Columnset(
        name    => "$csetName: padding",
        columns => \@padding,
      );
    push @tables,
      my $increaseColumnset = Columnset(
        name    => "$csetName: increases",
        columns => \@increase,
      );
    push @tables,
      my $decreaseColumnset = Columnset(
        name    => "$csetName: decreases",
        columns => \@decrease,
      );

    for my $r ( $rows->indices ) {
        next if $rows->{groupid} && !defined $rows->{groupid}[$r];
        local $_ = $rows->{list}[$r];
        if ($chartTitlesMaybe) {
            $_ = $chartTitlesMaybe->{$_};
        }
        else {
            s/.*\n//s;
            $_ = "$csetName for $_";
        }
        push @charts,
          SpreadsheetModel::WaterfallChart->new(
            name           => $_,
            scaling_factor => $settings->{scaling_factor},
            $settings->{instructions}
            ? ( instructions => [ @{ $settings->{instructions} } ] )
            : (),
            grey_rightwards =>
              SpreadsheetModel::ChartSeries->new( $valueColumnset, $r ),
            grey_leftwards =>
              SpreadsheetModel::ChartSeries->new( $valueNegColumnset, $r ),
            padding =>
              SpreadsheetModel::ChartSeries->new( $paddingColumnset, $r ),
            blue_rightwards =>
              SpreadsheetModel::ChartSeries->new( $increaseColumnset, $r ),
            orange_leftwards =>
              SpreadsheetModel::ChartSeries->new( $decreaseColumnset, $r ),
          );
    }

    \@tables, \@charts;

}

1;
