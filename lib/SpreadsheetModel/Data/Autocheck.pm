﻿package SpreadsheetModel::Data::Autocheck;

=head Copyright licence and disclaimer

Copyright 2016 Franck Latrémolière, Reckon LLP and others.

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
use Encode;
use File::Spec;
use Fcntl qw(:flock :seek);
use File::Spec::Functions qw(catfile);

use constant { C_TSV => 0, };

sub new {
    my ( $class, $homeFolder ) = @_;
    bless [ File::Spec->catfile( $homeFolder, 't', 'checks.tsv' ), ], $class;
}

sub check {

    my ( $autocheck, $book, $tableNumber, $checksumType, $checksum ) = @_;

    ( undef, undef, my $file ) = File::Spec->splitpath($book);
    $file =~ s/\.xlsx?$//si;
    my $revision = '';
    $file =~ s/\+$//s;
    $revision = $1 if $file =~ s/[+-](r[0-9]+)$//si;
    my $company = '';
    my $year    = '';
    ( $company, $year ) = ( $1, $2 )
      if $file =~ s/^(.+)-(20[0-9]{2}-[0-9]{2})-//s;

    my @records;
    my $fh;
    open $fh,      '+<', $autocheck->[C_TSV]
      or open $fh, '<',  $autocheck->[C_TSV]
      or die "Could not open $autocheck->[C_TSV]";
    flock $fh, LOCK_EX or die;
    local $/ = "\n";
    @records = <$fh>;
    chomp foreach @records;

    foreach (@records) {
        my @a = split /\t/;
        next unless @a > 4;
        if (   $a[0] eq $file
            && $a[1] eq $year
            && $a[2] eq $company
            && $a[3] == $tableNumber )
        {
            return if $a[4] eq $checksum;
            die "***\n"
              . "Wrong checksum for $book table $tableNumber\n"
              . "Expected $a[4], got $checksum\n";
        }
    }
    push @records, join "\t", $file, $year, $company, $tableNumber, $checksum,
      $revision ? $revision : ();
    seek $fh, 0, SEEK_SET;
    print {$fh} map { "$_\n"; } sort @records;

}

sub checkerOld {
    my ($autocheck) = @_;
    sub {
        my ( $book, $workbook ) = @_;
        for my $worksheet ( $workbook->worksheets() ) {
            my ( $row_min, $row_max ) = $worksheet->row_range();
            my ( $col_min, $col_max ) = $worksheet->col_range();
            my $tableNumber = 0;
            for my $row ( $row_min .. $row_max ) {
                my $rowName;
                for my $col ( $col_min .. $col_max ) {
                    my $cell = $worksheet->get_cell( $row, $col );
                    my $v;
                    $v = $cell->unformatted if $cell;
                    next unless defined $v;
                    eval { $v = Encode::decode( 'UTF-16BE', $v ); }
                      if $v =~ m/\x{0}/;
                    if ( !$col && $v =~ /^([0-9]+)\. /s ) {
                        $tableNumber = $1;
                    }
                    elsif ( $v =~ /^Table checksum ([0-9]{1,2})$/si ) {
                        my $checksumType = $1;
                        my $checksumCell =
                          $worksheet->get_cell( $row + 1, $col );
                        $autocheck->check( $book, $tableNumber, $checksumType,
                            $checksumCell->unformatted )
                          if $checksumCell;
                    }
                }
            }
        }
    };
}

sub checker {
    my ($autocheck) = @_;
    my @tableNumber;
    my @checksumLocation;
    my $book;
    (
        sub { },
        Setup => sub { $book = $_[0]; },
        NotSetCell  => 1,
        CellHandler => sub {
            my ( $wbook, $sheetIdx, $row, $col, $cell ) = @_;
            my $v;
            $v = $cell->unformatted if $cell;
            return unless defined $v;
            eval { $v = Encode::decode( 'UTF-16BE', $v ); }
              if $v =~ m/\x{0}/;
            if ( !$col && $v =~ /^([0-9]+)\. /s ) {
                local $_ = $1;
                return 1 unless /^(?:15|16|37|45)/;
                $tableNumber[$sheetIdx] = $_;
            }
            elsif ($checksumLocation[$sheetIdx]
                && $checksumLocation[$sheetIdx][0] == $row
                && $checksumLocation[$sheetIdx][1] == $col )
            {
                $autocheck->check( $book, $tableNumber[$sheetIdx],
                    $checksumLocation[$sheetIdx][2], $v );
            }
            elsif ( $v =~ /^Table checksum ([0-9]{1,2})$/si ) {
                $checksumLocation[$sheetIdx] = [ $row + 1, $col, $1 ];
            }
            0;
        }
    );
}

1;

