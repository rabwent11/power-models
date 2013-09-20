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
require Spreadsheet::WriteExcel::Utility;
use SpreadsheetModel::Shortcuts ':all';

require POSIX;

sub worksheetsAndClosures {

    my ( $model, $wbook ) = @_;

    $wbook->{lastSheetNumber} = 11;

    'Input' => sub {
        my ($wsheet) = @_;
        $wsheet->{sheetNumber} = 12;
        $wsheet->freeze_panes( 1, 0 );
        $wsheet->set_column( 0, 0,   48 );
        $wsheet->set_column( 1, 250, 20 );
        return if $model->{oneSheet};
        $wsheet->{nextFree} = 1;
        $model->{inputTables} ||= [];
        my $te = Dataset(
            number        => 1200,
            dataset       => $model->{dataset},
            name          => 'Data version',
            cols          => Labelset( list => [qw(Version)] ),
            defaultFormat => 'texthard',
            data          => ['Illustrative']
        );
        my ( $sh, $ro, $co ) = $te->wsWrite( $wbook, $wsheet );

        # require Spreadsheet::WriteExcel::Utility;
        $sh = $sh->get_name;
        {
            $wbook->{titleAppend} =
              qq%" for "&'$sh'!%
              . Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell( $ro, $co );
        }
        $_->wsWrite( $wbook, $wsheet )
          foreach sort { ( $a->{number} || 9909 ) <=> ( $b->{number} || 9909 ) }
          @{ $model->{inputTables} };
        my $nextFree = delete $wsheet->{nextFree};
        Notes( lines => [ 'General input data', '', ] )
          ->wsWrite( $wbook, $wsheet );
        $wsheet->{nextFree} = $nextFree;
      }

      ,

      (
        map {
            (
                $_ => sub {
                    my ($wsheet) = @_;
                    $wsheet->freeze_panes( 1, 0 );
                    $wsheet->set_column( 0, 0,   12 );
                    $wsheet->set_column( 1, 1,   42 );
                    $wsheet->set_column( 2, 250, 20 );
                    $_->wsWrite( $wbook, $wsheet )
                      foreach Notes( name => $model->{dnoData}{$_}{name} ),
                      $model->{dnoData}{$_};
                }
            );
        } sort keys %{ $model->{dnoData} }
      )

      ,

      $model->{filterTables}
      ? (
        Filter => sub {
            my ($wsheet) = @_;
            $wsheet->freeze_panes( 1, 0 );
            $wsheet->set_column( 0, 0,   12 );
            $wsheet->set_column( 1, 1,   42 );
            $wsheet->set_column( 2, 250, 20 );
            $_->wsWrite( $wbook, $wsheet )
              foreach Notes( name => "Filtering" ),
              @{ $model->{filterTables} };
        }
      )
      : ()

      ,

      (
        map {
            my $part = $_;my @labels=
              $model->{calcSheetNames} ? @{$model->{calcSheetNames}[$_]} : (1+$_,1+$_);
            "Calc$labels[0]" => sub {
                my ($wsheet) = @_;
                $wsheet->freeze_panes( 1, 0 );
                $wsheet->set_column( 0, 250, 20 );
                $_->wsWrite( $wbook, $wsheet )
                  foreach Notes( name => "Calculations part $labels[1]" ),
                  @{ $model->{calcTables}[ $part ] };
            };
        } 0 .. $#{ $model->{calcTables} }
      )

      ,

      'Results' => sub {
        my ($wsheet) = @_;
        $wsheet->freeze_panes( 1, 0 );
        $wsheet->set_column( 0, 0,   42 );
        $wsheet->set_column( 1, 250, 20 );
        $_->wsWrite( $wbook, $wsheet )
          foreach Notes( name => 'Results' ), @{ $model->{resultsTables} };
      }

      ,

      $model->{oneSheet} ? ( 'All' => sub { } ) : (
        'Index' => sub {

            my ($wsheet) = @_;
            $wsheet->freeze_panes( 1, 0 );
            $wsheet->fit_to_pages( 1, 2 );
            $wsheet->set_column( 0, 0,   30 );
            $wsheet->set_column( 1, 1,   90 );
            $wsheet->set_column( 2, 250, 30 );
            $model->frontPageNotices->wsWrite( $wbook, $wsheet );

            $wsheet->write_string(
                2, 2,
                'Colour coding',
                $wbook->getFormat('thc')
            );
            $wsheet->write_string( 3, 2, 'Data input',
                $wbook->getFormat('0.000hard') );
            $wsheet->write_string(
                4, 2,
                'Unused cell in input data table',
                $wbook->getFormat('unused')
            );
            $wsheet->write_string( 5, 2, 'Calculation',
                $wbook->getFormat('0.000soft') );
            $wsheet->write_string( 6, 2, 'Copy data',
                $wbook->getFormat('0.000copy') );
            $wsheet->write_string(
                7, 2,
                'Unused cell in calculation table',
                $wbook->getFormat('unavailable')
            );
            $wsheet->write_string(
                8, 2,
                'Constant value',
                $wbook->getFormat('0.000con')
            );
            $wsheet->write_string(
                9, 2,
                'Unlocked cell for notes',
                $wbook->getFormat('scribbles')
            );

            $wbook->{logger}->wsWrite( $wbook, $wsheet );

            local $/ = "\n";

            Notes(
                name       => '',
                rowFormats => ['caption'],
                lines      => [
                    'Model identification and configuration',
                    $model->{yaml},
                    '',
                    'Generated on '
                      . POSIX::strftime( '%a %e %b %Y %H:%M:%S',
                        @{ $model->{localTime} } )
                      . ( $ENV{SERVER_NAME} ? " by $ENV{SERVER_NAME}" : '' ),
                ]
            )->wsWrite( $wbook, $wsheet );

        }
      );

}

sub frontPageNotices {
    my ($model) = @_;
    Notes(
        name  => 'Index',
        lines => [
            <<'EOL',

Any redistribution of this software must retain the following disclaimer:

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

The code used to generate this spreadsheet is open-source software
published at https://github.com/f20/power-models.  Use and distribution 
of the source code is subject to the conditions stated therein. 

EOL
        ]
    );
}

1;
