﻿package ModelM::MultiModel;

=head Copyright licence and disclaimer

Copyright 2011 The Competitive Networks Association and others.
Copyright 2014 Franck Latrémolière.

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

sub new {
    bless { virgin => 1 }, shift;
}

sub addModelName {
    push @{ $_[0]{modelNames} }, $_[1];
}

sub addImpactTableSet {
    push @{ $_[0]{impactTableSets} }, $_[1];
}

sub worksheetsAndClosuresWithController {

    my ( $mms, $model, $wbook, @pairs ) = @_;

    return @pairs unless delete $mms->{virgin};

    'Control$' => sub {
        my ($wsheet) = @_;
        $wsheet->{sheetNumber} = 14;
        $wsheet->freeze_panes( 1, 0 );
        $wsheet->set_column( 0, 0,   60 );
        $wsheet->set_column( 1, 250, 20 );
        $_->wsWrite( $wbook, $wsheet ) foreach Notes(
            name  => 'Controller',
            lines => $model->illustrativeNotice,
          ),
          $model->licenceNotes,
          @{ $mms->{optionsColumns} };

        $mms->{finish} = sub {
            delete $wbook->{logger};
            my $modelNameset = Labelset( list => $mms->{modelNames} );
            $_->wsWrite( $wbook, $wsheet ) foreach map {
                my $tableNo    = $_;
                my $leadTable  = $mms->{impactTableSets}[0][$tableNo];
                my $leadColumn = $leadTable->{columns}[0] || $leadTable;
                my ( $sh, $ro, $co ) = $leadColumn->wsWrite( $wbook, $wsheet );
                $sh = $sh->get_name;
                my $colset = Labelset(
                    list => [
                        map {
                            qq%='$sh'!%
                              . Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                                $ro - 1, $co + $_ )
                        } 0 .. $#{ $leadTable->{columns} }
                    ]
                );
                my $defaultFormat = $leadTable->{defaultFormat}
                  || $leadTable->{columns}[0]{defaultFormat};
                $defaultFormat =~ s/soft/copy/
                  unless $defaultFormat =~ /pm$/;
                Constant(
                    name          => "From $leadTable->{name}",
                    defaultFormat => $defaultFormat,
                    rows          => $modelNameset,
                    cols          => $colset,
                    byrow         => 1,
                    data          => [
                        map {
                            my $table = $_->[$tableNo];
                            my ( $sh, $ro, $co ) =
                              $table->{columns}[0]->wsWrite( $wbook, $wsheet );
                            $sh = $sh->get_name;
                            [
                                map {
                                    qq%='$sh'!%
                                      . Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                                        $ro, $co + $_ );
                                } 0 .. $#{ $leadTable->{columns} }
                            ];
                        } @{ $mms->{impactTableSets} }
                    ]
                );
            } 0 .. $#{ $mms->{impactTableSets}[0] };
        };

      },

      @pairs;

}

sub finish {
    $_[0]->{finish}->();
}

1;