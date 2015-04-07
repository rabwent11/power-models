﻿package SpreadsheetModel::Export::TableMap;

=head Copyright licence and disclaimer

Copyright 2015 Franck Latrémolière, Reckon LLP and others.

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
use Fcntl qw(:flock);

sub updateTableMap {
    my ( $model, $modelName ) = @_;
    $modelName =~ s#.*/##s;
    my ( %list, @columns, $fh );
    open $fh,      '+<', '~$tablemap.tsv'
      or open $fh, '+>', '~$tablemap.tsv'
      or die 'Cannot use ~$tablemap.tsv: ' . $!;
    flock $fh, LOCK_EX;
    binmode $fh;
    local $/ = "\n";
    if ( defined( local $_ = <$fh> ) ) {
        chomp;
        @columns = split /\t/;
        splice @columns, 0, 2;
    }
    while (<$fh>) {
        chomp;
        my @a = split /\t/;
        my $k = join "\t", splice @a, 0, 2;
        $list{$k} = \@a;
    }
    push @columns, $modelName;
    foreach my $obj ( $model->{logger}->loggableObjects ) {
        my $name   = "$obj->{name}";
        my $number = '';
        $number = $1 if $name =~ s/^([0-9]+)\.\s*//s;
        $name =~ tr/\t/ /;
        my $ref = $obj->{debug};
        $ref =~ s#.*/lib/##s;
        $list{ join "\t", $name, $ref }[$#columns] = $number;
    }
    my %sort;
    while ( my ( $k, $v ) = each %list ) {
        my ($lowest) =
          ( sort grep { $_; } @$v )[0] || 'none';
        $sort{$k} = join "\t", $lowest, $k;
    }
    my @keys = sort { $sort{$a} cmp $sort{$b} } keys %sort;
    seek $fh, 0, 0;
    truncate $fh, 0;
    print {$fh} join( "\t", 'Name', 'Code reference', @columns ) . "\n";
    print {$fh}
      join( "\t", $_, map { $_ || ''; } @{ $list{$_} }[ 0 .. $#columns ] )
      . "\n"
      foreach @keys;
    my $wbmodule = 'SpreadsheetModel::Workbook';
    if ( eval "require $wbmodule" ) {
        my $wb = $wbmodule->new( '_Table map' . $wbmodule->fileExtension );
        $wb->setFormats();
        my $ws = $wb->add_worksheet('Table mapping');
        $ws->set_column( 0, 0,   72 );
        $ws->set_column( 1, 1,   48 );
        $ws->set_column( 2, 254, 12 );
        $ws->hide_gridlines(2);
        $ws->freeze_panes( 1, 2 );
        $ws->write_string( 0, 0,      'Name',           $wb->getFormat('thc') );
        $ws->write_string( 0, 1,      'Code reference', $wb->getFormat('thc') );
        $ws->write_string( 0, 2 + $_, $columns[$_],     $wb->getFormat('thc') )
          foreach 0 .. $#columns;

        my $row = 1;
        foreach (@keys) {
            my $col = -1;
            $ws->write( $row, ++$col, $_ ) foreach split(/\t/), @{ $list{$_} };
            ++$row;
        }
        $ws->autofilter( 0, 0, $row - 1, 2 + $#columns );
    }
    flock $fh, LOCK_UN;
}

1;
