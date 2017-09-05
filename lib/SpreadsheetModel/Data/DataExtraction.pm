﻿package SpreadsheetModel::Data::DataExtraction;

=head Copyright licence and disclaimer

Copyright 2008-2017 Franck Latrémolière, Reckon LLP and others.

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

sub ymlWriter {
    my ($arg) = @_;
    my $options = { $arg =~ /min/i ? ( minimum => 1 ) : (), };
    sub {
        my ( $book, $workbook ) = @_;
        die unless $book;
        my $file = $book;
        $file =~ s/\.xl[a-z]+?$//is;
        my $tree;
        require YAML;
        if ( my ($oldYaml) = grep { -f $_; } "$file.yml", "$file.yaml" ) {
            open my $h, '<', $oldYaml;
            binmode $h, ':utf8';
            local undef $/;
            $tree = YAML::Load(<$h>);
        }
        my %trees = _extractInputData( $workbook, $tree, $options );
        while ( my ( $key, $value ) = each %trees ) {
            open my $h, '>', "$file$key.yml";
            binmode $h, ':utf8';
            print $h YAML::Dump($value);
        }
    };
}

sub rebuildWriter {
    my ( $arg, $runner ) = @_;
    sub {
        my ( $fileName, $workbook ) = @_;
        die unless $fileName;
        my ( $path, $core, $ext ) = $fileName =~ m#(.*/)?([^/]+)(\.xlsx?)$#is;
        $path = '' unless defined $path;
        my $tempFolder = $path . $core . '-' . $$ . '.tmp';
        my $sidecar    = $path . $core;
        undef $sidecar unless -d $sidecar && -w _;
        unless ( defined $sidecar ) {
            $sidecar = $path . '~$' . $core;
            undef $sidecar unless -d $sidecar && -w _;
        }
        mkdir $tempFolder or die "Cannot create $tempFolder: $!";
        my $rulesFile;
        if ( defined $sidecar ) {
            $rulesFile = "$sidecar/%-$core.yml";
            undef $rulesFile unless -f $rulesFile;
            unless ( defined $rulesFile ) {
                $rulesFile = "$sidecar/%.yml";
                undef $rulesFile unless -f $rulesFile;
            }
        }
        require YAML;
        {
            my ( $h1, $h2 );
            open $h1, '>', "$tempFolder/index-$core.yml";
            binmode $h1, ':utf8';
            unless ( defined $rulesFile ) {
                open $h2, '>', $rulesFile = "$tempFolder/%-$core.yml";
                binmode $h2, ':utf8';
            }
            foreach ( _extractYaml($workbook) ) {
                print $h1 $_;
                if ($h2) {
                    my $rules = YAML::Load($_);
                    delete $rules->{$_}
                      foreach 'template', grep { /^~/s } keys %$rules;
                    print {$h2} YAML::Dump($rules);
                }
            }
        }
        my %trees = _extractInputData($workbook);
        while ( my ( $key, $value ) = each %trees ) {
            open my $h, '>', "$tempFolder/$core$key.yml";
            binmode $h, ':utf8';
            print $h YAML::Dump($value);
        }
        $runner->makeModels(
            '-pickall', '-single',
            lc $ext eq '.xls' ? '-xls' : '-xlsx', "-folder=$tempFolder",
            "-template=%", $rulesFile,
            "$tempFolder/$core.yml"
        );
        if ( -s "$tempFolder/$core$ext" ) {
            rename "$path$core$ext", "$tempFolder/$core-old$ext"
              unless defined $sidecar;
            rename "$tempFolder/$core$ext", "$path$core$ext"
              or warn "Cannot move $tempFolder/$core$ext to $path$core$ext: $!";
        }
        if ( defined $sidecar ) {
            my $dh;
            opendir $dh, $tempFolder;
            foreach ( readdir $dh ) {
                next if /^\.\.?$/s;
                rename "$tempFolder/$_", "$sidecar/$_";
            }
            closedir $dh;
            rmdir $tempFolder;
        }
        else {
            rename $tempFolder, $path . "Z_Rebuild-$core-$$";
        }
      }
}

my $jsonMachine;

sub jsonMachineMaker {
    return $jsonMachine if $jsonMachine;
    foreach (qw(JSON JSON::PP)) {
        return $jsonMachine = $_->new
          if eval "require $_";
    }
    die 'No JSON module';
}

sub jsonWriter {
    my ($arg) = @_;
    my $jsonMachine = jsonMachineMaker()->canonical(1)->pretty->utf8;
    my $options = { $arg =~ /min/i ? ( minimum => 1 ) : (), };
    sub {
        my ( $book, $workbook ) = @_;
        die unless $book;
        my $file = $book;
        $file =~ s/\.xl[a-z]+?$//is;
        my $tree;
        if ( -e $file ) {
            open my $h, '<', "$file.json";
            binmode $h;
            local undef $/;
            $tree = $jsonMachine->decode(<$h>);
        }
        my %trees = _extractInputData( $workbook, $tree, $options );
        while ( my ( $key, $value ) = each %trees ) {
            open my $h, '>', "$file$key.json";
            binmode $h;
            print {$h} $jsonMachine->encode($value);
        }
    };
}

sub _extractYaml {
    my ($workbook) = @_;
    my @yamlBlobs;
    my $current;
    for my $worksheet ( $workbook->worksheets() ) {
        my ( $row_min, $row_max ) = $worksheet->row_range();
        my ( $tableNumber, $evenIfLocked, $columnHeadingsRow, $to1, $to2 );
        for my $row ( $row_min .. $row_max ) {
            my $rowName;
            my $cell = $worksheet->get_cell( $row, 0 );
            my $v;
            $v = $cell->unformatted if $cell;
            next unless defined $v;
            eval { $v = Encode::decode( 'UTF-16BE', $v ); }
              if $v =~ m/\x{0}/;
            if ($current) {
                if ( $v eq '' ) {
                    push @yamlBlobs, $current;
                    undef $current;
                }
                else {
                    $current .= "$v\n";
                }
            }
            elsif ( $v eq '---' ) {
                $current = "$v\n";
            }
        }
        if ($current) {
            push @yamlBlobs, $current;
            undef $current;
        }
    }
    @yamlBlobs;
}

sub _extractInputData {
    my ( $workbook, $tree, $options ) = @_;
    my ( %byWorksheet, %used );
    my $conflictStatus = 0;
    for my $worksheet ( $workbook->worksheets() ) {
        my ( $row_min, $row_max ) = $worksheet->row_range();
        my ( $col_min, $col_max ) = $worksheet->col_range();
        my ( $tableNumber, $evenIfLocked, $columnHeadingsRow, $to1, $to2 );
        for my $row ( $row_min .. $row_max ) {
            my $rowName;
            for my $col ( $col_min .. $col_max ) {
                my $cell = $worksheet->get_cell( $row, $col );
                my $v;
                $v = $cell->unformatted if $cell;
                $evenIfLocked = 1
                  if $col == 0
                  && !$v
                  && defined $evenIfLocked
                  && !$evenIfLocked;
                next unless defined $v;
                eval { $v = Encode::decode( 'UTF-16BE', $v ); }
                  if $v =~ m/\x{0}/;
                if ( $col == 0 ) {
                    if ( !ref $cell->{Format} || $cell->{Format}{Lock} ) {
                        if ( $v =~ /^[0-9]{3,}\. .*⇒([0-9]{3,})/
                            && !( $evenIfLocked = 0 )
                            || $v =~ /^([0-9]{3,})\. /
                            && !( undef $evenIfLocked ) )
                        {
                            $tableNumber = $1;
                            undef $columnHeadingsRow;
                            $to2 = [];
                            $conflictStatus = defined $evenIfLocked ? 1 : 2
                              if $used{$tableNumber} && $conflictStatus < 2;
                            $to1 =
                              $used{$tableNumber}
                              ? [ map { +{%$_}; } @{ $tree->{$tableNumber} } ]
                              : $to2;
                            $used{$tableNumber} = 1;
                            $to1->[0]{_table} = $to2->[0]{_table} = $v
                              unless $options->{minimum};
                        }
                        elsif ($v) {
                            $v =~ s/[^A-Za-z0-9-]/ /g;
                            $v =~ s/- / /g;
                            $v =~ s/ +/ /g;
                            $v =~ s/^ //;
                            $v =~ s/ $//;
                            $rowName =
                              $v eq ''
                              ? 'Anon' . ( ( $columnHeadingsRow || 0 ) - $row )
                              : $v;
                        }
                        else {
                            undef $tableNumber;
                        }
                    }
                    elsif ( $worksheet->{Name} !~ /^(?:Index|Overview)$/s )
                    {    # unlocked cell in column 0
                        if ( defined $tableNumber ) {
                            next unless defined $columnHeadingsRow;
                            $rowName = $row - $columnHeadingsRow;
                            $to1->[0]{$rowName} = $to2->[0]{$rowName} = $v;
                        }
                        else {
                            $tableNumber       = '!';
                            $columnHeadingsRow = $row;
                        }
                    }
                }
                elsif ( defined $tableNumber ) {
                    if ( !defined $rowName ) {
                        $columnHeadingsRow = $row;
                        if ( $options->{minimum} ) {
                            $to1->[$col] ||= {};
                        }
                        else {
                            $to1->[$col]{'_column'} = $v;
                            $to2->[$col]{'_column'} = $v;
                        }
                    }
                    elsif ( $evenIfLocked
                        || ref $cell->{Format} && !$cell->{Format}{Lock}
                        and $v
                        || $to1->[$col] )
                    {
                        $to1->[$col]{$rowName} = $to2->[$col]{$rowName} = $v;
                        $tree->{$tableNumber} ||= $to2;
                        $byWorksheet{' combined'}{$tableNumber} = $to1
                          if $evenIfLocked;
                        $byWorksheet{" $worksheet->{Name}"}{$tableNumber} =
                          $to2;
                    }
                }
            }
        }
    }
    '', $tree,
       !$conflictStatus ? ()
      : $conflictStatus == 1 ? ( ' combined' => $byWorksheet{' combined'} )
      :                        %byWorksheet;
}

sub databaseWriter {

    my ($settings) = @_;

    my $db;
    my $s;
    my $bid;

    my $writer = sub {
        $s->execute( $bid, @_ );
    };

    my $commit = sub {
        sleep 1 while !$db->do('commit');
    };

    my $newBook = sub {
        require SpreadsheetModel::Data::Database;
        $db = SpreadsheetModel::Data::Database->new(1);
        sleep 1 while !$db->do('begin immediate transaction');
        $bid = $db->addModel( $_[0] );
        sleep 1 while !$db->commit;
        sleep 1 while !$db->do('begin transaction');
        sleep 1
          while !(
            $s = $db->prepare(
                    'insert into data (bid, tab, row, col, v)'
                  . ' values (?, ?, ?, ?, ?)'
            )
          );
    };

    my $processTable = sub { };

    my $yamlCounter = -1;
    my $processYml  = sub {
        my @a;
        while ( my $b = shift ) {
            push @a, $b->[0];
        }
        $writer->( 0, 0, ++$yamlCounter, join "\n", @a, '' );
        $processTable = sub { };
    };

    sub {

        my ( $book, $workbook ) = @_;

        if ( !defined $book ) {    # pruning
            require SpreadsheetModel::Data::Database;
            $db ||= SpreadsheetModel::Data::Database->new(1);
            my $gbid;
            sleep 1
              while !(
                $gbid = $db->prepare(
                        'select bid, filename from books '
                      . 'where filename like ? order by filename'
                )
              );
            foreach ( split /:/, $workbook ) {
                $gbid->execute($_);
                while ( my ( $bid, $filename ) = $gbid->fetchrow_array ) {
                    warn "Deleting $filename";
                    my $a = 'y';    # could be <STDIN>
                    if ( $a && $a =~ /y/i ) {
                        warn $db->do( 'delete from books where bid=?',
                            undef, $bid ),
                          ' ',
                          $db->do( 'delete from data where bid=?',
                            undef, $bid );
                    }
                }
            }
            $commit->();
            return;
        }

        $newBook->($book);

        warn "process $book ($$)\n";
        for my $worksheet ( $workbook->worksheets() ) {
            next
              if $settings->{sheetFilter}
              && !$settings->{sheetFilter}->($worksheet);
            my ( $row_min, $row_max ) = $worksheet->row_range();
            my ( $col_min, $col_max ) = $worksheet->col_range();
            my $tableTop = 0;
            my @table;
            for my $row ( $row_min .. $row_max ) {
                for my $col ( $col_min .. $col_max ) {
                    my $cell = $worksheet->get_cell( $row, $col );
                    next unless $cell;
                    my $v = $cell->unformatted;
                    next unless defined $v;
                    eval { $v = Encode::decode( 'UTF-16BE', $v ); }
                      if $v =~ m/\x{0}/;
                    if ( $col == 0 ) {

                        if ( $v eq '---' ) {
                            $processTable->(@table) if @table;
                            $tableTop     = $row;
                            @table        = ();
                            $processTable = $processYml;
                        }
                        elsif ( $v =~ /^([0-9]{2,})\. / ) {
                            $processTable->(@table) if @table;
                            $tableTop = $row;
                            @table    = ();
                            my $tableNumber = $1;
                            $processTable = sub {
                                my $offset = $#_;
                                --$offset
                                  while !$_[$offset]
                                  || @{ $_[$offset] } < 2;
                                --$offset
                                  while $offset && defined $_[$offset][0];

                                for my $row ( 0 .. $#_ ) {
                                    my $r  = $_[$row];
                                    my $rn = $row - $offset;
                                    for my $col ( 0 .. $#$r ) {
                                        $writer->(
                                            $tableNumber, $rn, $col, $r->[$col]
                                        ) if defined $r->[$col];
                                    }
                                }

                                $processTable = sub { };
                            };
                        }
                    }
                    $table[ $row - $tableTop ][$col] = $v;
                }
            }
            $processTable->(@table) if @table;
        }
        eval {
            warn "commit $book ($$)\n";
            $commit->();
        };
        warn "$@ for $book ($$)\n" if $@;

    };

}

sub jbzWriter {

    my $set;
    $set = sub {
        my ( $scalar, $key, $sha1hex ) = @_;
        if ( $key =~ s#^([^/]*)/## ) {
            $set->( $scalar->{$1} ||= {}, $key, $sha1hex );
        }
        else {
            $scalar->{$key} = $sha1hex;
        }
    };

    sub {
        my ( $book, $workbook ) = @_;
        my %scalars;
        for my $worksheet ( $workbook->worksheets() ) {
            my $scalar = {};
            my ( $row_min, $row_max ) = $worksheet->row_range();
            for my $row ( $row_min .. $row_max ) {
                if ( my $cell = $worksheet->get_cell( $row, 0 ) ) {
                    if ( my $v = $cell->unformatted ) {
                        if ( $v =~ /(\S+): ([0-9a-fA-F]{40})/ ) {
                            $set->(
                                $scalar,
                                $1 eq 'validation' ? 'dataset.yml' : $1, $2
                            );
                        }
                    }
                }
            }
            $scalars{ $worksheet->{Name} } = $scalar if %$scalar;
        }
        return unless %scalars;
        my $jsonModule;
        if    ( eval 'require JSON' )     { $jsonModule = 'JSON'; }
        elsif ( eval 'require JSON::PP' ) { $jsonModule = 'JSON::PP'; }
        else { warn 'No JSON module found'; goto FAIL; }
        $book =~ s/\.xl\S+//i;
        $book .= '.jbz';
        $book =~ s/'/'"'"'/g;
        open my $fh, qq%|bzip2>'$book'% or goto FAIL;
        binmode $fh or goto FAIL;
        print {$fh}
          $jsonModule->new->canonical(1)
          ->utf8->pretty->encode(
            keys %scalars > 1 ? \%scalars : values %scalars )
          or goto FAIL;
        return;
      FAIL: warn $!;
        return;
    };

}

sub rulesWriter {
    sub {
        my ( $book, $workbook ) = @_;
        $book =~ s/\.xl\S+//i;
        $book .= '-rules.yml';
        open my $fh, '>', $book . $$;
        binmode $fh;
        print {$fh} _extractYaml($workbook);
        close $fh;
        rename $book . $$, $book;
    };
}

1;

