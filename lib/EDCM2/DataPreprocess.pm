﻿package EDCM2;

# Copyright 2009-2011 Energy Networks Association Limited and others.
# Copyright 2012-2020 Franck Latrémolière, Reckon LLP and others.
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

sub preprocessDataset {

    my ($model) = @_;
    my $d = $model->{dataset} or return;
    $d->{datasetCallback}->($model) if $d->{datasetCallback};

    foreach (
        qw(numTariffs numLocations numExtraTariffs numSampleTariffs numExtraLocations)
      )
    {
        $model->{$_} = $d->{$_} if exists $d->{$_};
    }

    if (   $model->{method}
        && $model->{method} !~ /none/i )
    {
        if (
            my $ds = $d->{
                $model->{method} =~ /FCP/i ? 'sizing911'
                : 'sizing913'
            }
            || $d->{
                $model->{method} =~ /FCP/i ? 911
                : 913
            }
          )
        {
            my $h = $ds->[1];
            if ( ref $h eq 'HASH' ) {
                my $max = $model->{numLocations} || 0;
                foreach ( keys %$h ) {
                    if (   $h->{$_}
                        && lc $h->{$_} ne 'not used'
                        && $h->{$_} ne '#VALUE!'
                        && $h->{$_} !~ /^\s*$/s )
                    {
                        $max = $_ if /^[0-9]+$/ && $_ > $max;
                    }
                    else {
                        $h->{$_} = 'Not used';
                    }
                }
                $model->{numLocations} =
                  (      $model->{randomise}
                      || $model->{small}
                      || defined $model->{numLocations} ? 0 : 6 ) +
                  $max;
                foreach my $k ( 1 .. $model->{numLocations} ) {
                    exists $ds->[$_]{$k} || ( $ds->[$_]{$k} = '' )
                      foreach 0 .. $#$ds;
                }
            }
        }
    }

    if ( my $ds = $d->{sizing935} || $d->{935} ) {
        if ( ref $ds->[1] eq 'HASH' ) {
            my %tariffs;

            splice @$ds, 8, 0,
              $d->{t935dcp189}
              ? $d->{t935dcp189}[0]
              : {
                map { ( $_ => $model->{dcp189default} || '' ); }
                  keys %{ $ds->[1] }
              }
              if $model->{dcp189}
              and !$ds->[8]
              || !$ds->[8]{_column}
              || $ds->[8]{_column} !~ /reduction/i;

            splice @$ds, 23, 0,
              {
                map { ( $_ => '' ); }
                  keys %{ $ds->[1] }
              }
              if $model->{dcp342}
              and !$ds->[23]
              || !$ds->[23]{_column}
              || $ds->[23]{_column} !~ /exempt/i;

            splice @$ds, 23, 1,
              if !$model->{dcp342}
              and $ds->[23]
              || $ds->[23]{_column}
              || $ds->[23]{_column} =~ /exempt/i;

            my $max = 0;
            while ( my ( $k, $v ) = each %{ $ds->[1] } ) {
                next
                  unless $k =~ /^[0-9]+$/
                  && grep { $ds->[$_]{$k} && $ds->[$_]{$k} ne 'VOID'; } 2 .. 6
                  || $v
                  && lc $v ne 'not used'
                  && $v ne '#VALUE!'
                  && $v !~ /^\s*$/s;
                undef $tariffs{$k};
                $max = $k if $k > $max;
            }

            if ($max) {
                my $tariffs;
                if ( ref $model->{tariffs} eq 'ARRAY' ) {
                    $tariffs = $model->{tariffs};
                }
                elsif ($model->{numTariffs}
                    && $max <= $model->{numTariffs} )
                {
                    $tariffs = [ 1 .. $model->{numTariffs} ];
                }
                else {
                    $tariffs = [
                        $model->{randomise} || $model->{small}
                        ? ( sort { $a <=> $b } keys %tariffs )
                        : ( 1 .. $max ),
                        $model->{randomise}
                          || $model->{small}
                          || defined $model->{numTariffs} ? ()
                        : ( $max + 1 .. $max + 6 )
                    ];
                    push @$tariffs, $max + 1
                      unless $model->{transparency}
                      && $model->{transparency} =~ /impact/i
                      || @$tariffs > 1;
                }
                $model->{numTariffs} = @$tariffs;
                $model->{tariffSet}  = Labelset(
                    name          => 'Tariffs',
                    list          => $tariffs,
                    defaultFormat => 'thtar',
                );
                foreach my $k (@$tariffs) {
                    my $v = $ds->[1]{$k};
                    if ( grep { $ds->[$_]{$k} && $ds->[$_]{$k} ne 'VOID'; }
                        2 .. 6
                        || $v
                        && lc $v ne 'not used'
                        && $v ne '#VALUE!'
                        && $v ne '#N/A'
                        && $v ne 'VOID'
                        && $v !~ /^\s*$/s )
                    {
                        $ds->[$_]{$k} || ( $ds->[$_]{$k} = 'VOID' )
                          foreach 2 .. 6;
                        exists $ds->[$_]{$k} || ( $ds->[$_]{$k} = '' )
                          foreach 7 .. $#$ds;
                    }
                    else {
                        $ds->[1]{$k} = ' ';
                        $ds->[$_]{$k} = 'VOID' foreach 2 .. 6;
                        $ds->[$_]{$k} = ''     foreach 7 .. $#$ds;
                    }
                }
            }

            if ( $model->{nonames} ) {
                $ds->[1]{$_} = "Tariff $_" foreach keys %{ $ds->[1] };
            }
        }

    }

    return if $d->{datasetCallback};

    if (
            $model->{version}
        and $d->{1100}
        and ref $d->{1100}[3] eq 'HASH'
        and my ($key) =
        grep { !/^_/ } keys %{ $d->{1100}[3] }
      )
    {
        $d->{1100}[3]{$key} = $model->{version};
    }

    if ( $d->{1113} && $model->{revenueAdj} ) {
        my ($key) =
          grep { !/^_/ } keys %{ $d->{1113}[4] };
        $d->{1113}[4]{$key} += $model->{revenueAdj};
    }

    foreach ( 1037, 1039 ) {
        splice @{ $d->{$_} }, 1, 0, $d->{$_}[1]
          if $d->{$_} && $d->{$_}[1]{_column} && $d->{$_}[1]{_column} =~ /LV/;
    }

    if ( $model->{ldnoRev} && $model->{ldnoRev} =~ /nopop/i ) {
        delete $d->{$_} foreach qw(1181 1182 1183);
    }

    if ( my @tables = grep { $_ } @{$d}{qw(1133 1134 1136)} ) {
        if ( $model->{tableGrouping} || $model->{transparency} ) {
            foreach (
                grep {
                        !$_->[1]{_column} && $_->[6]
                      || $_->[1]{_column}
                      && $_->[1]{_column} =~ /GSP/
                } @tables
              )
            {
                splice @$_, 1, 1;
            }
        }
        else {
            foreach ( grep { $_->[1]{_column} && $_->[1]{_column} !~ /GSP/ }
                @tables )
            {
                splice @$_, 1, 0, $_->[1];
                foreach my $k ( keys %{ $_->[1] } ) {
                    $_->[1]{$k} = $k eq '_column' ? 'GSP' : '';
                }
            }
        }
        if ( $d->{1136} ) {
            $d->{1133} ||= [
                map {
                    my %a;
                    if ($_) {
                        while ( my ( $k, $v ) = each %$_ ) {
                            $a{$k} = $v if $k eq '_column' || $k =~ /maximum/i;
                        }
                    }
                    \%a;
                } @{ $d->{1136} }
            ];
            $d->{1134} ||= [
                map {
                    my %a;
                    if ($_) {
                        while ( my ( $k, $v ) = each %$_ ) {
                            $a{$k} = $v if $k eq '_column' || $k =~ /minimum/i;
                        }
                    }
                    \%a;
                } @{ $d->{1136} }
            ];
        }
        else {
            my $a = $d->{1136} =
              $d->{1133} || $d->{1134};
            foreach (qw(1133 1134)) {
                my $t = $d->{$_} or next;
                my ($k1) = grep { !/^_/ } keys %{ $t->[1] } or next;
                my $k2 = ( $_ == 1133 ? 'Maximum' : 'Minimum' )
                  . ' network use factor';
                for ( my $c = 1 ; $c < @$t ; ++$c ) {
                    $a->[$c]{$k2} = $t->[$c]{$k1};
                }
            }
        }
    }

    if ( $d->{1113} ) {
        my ($k1113) = grep { !/^_/ } keys %{ $d->{1113}[1] };
        $d->{1101} ||= [
            undef,
            @{ $d->{1113} }[ 2, 6, 7, 8 ],
            {
                $k1113 => $d->{1113}[4]{$k1113} + $d->{1113}[5]{$k1113}
            },
            $d->{1113}[5]
        ];
        $d->{1110} ||=
          [ undef, @{ $d->{1113} }[ 1, 3 ] ];
        $d->{1118} ||=
          [ undef, @{ $d->{1113} }[ 9 .. 12 ] ];
    }
    elsif ( my ($k1101) = grep { !/^_/ } keys %{ $d->{1101}[1] } ) {
        $d->{1113} ||= [
            undef,
            $d->{1110}[1],
            $d->{1101}[1],
            $d->{1110}[2],
            {
                $k1101 => $d->{1101}[5]{$k1101} - $d->{1101}[6]{$k1101}
            },
            @{ $d->{1101} }[ 6, 2, 3, 4 ],
            @{ $d->{1118} }[ 1 .. 4 ],
        ];
    }

    if ( $d->{1140} ) {
        $d->{1105} ||= [
            map {
                my %a;
                if ($_) {
                    while ( my ( $k, $v ) = each %$_ ) {
                        $a{$k} = $v if $k eq '_column' || $k =~ /diversity/i;
                    }
                }
                \%a;
            } @{ $d->{1140} }
        ];
        $d->{1122} ||= [
            map {
                my %a;
                if ($_) {
                    while ( my ( $k, $v ) = each %$_ ) {
                        $a{$k} = $v if $k eq '_column' || $k =~ /simultaneous/i;
                    }
                }
                \%a;
            } @{ $d->{1140} }
        ];
        $d->{1131} ||= [
            map {
                my %a;
                if ($_) {
                    while ( my ( $k, $v ) = each %$_ ) {
                        $a{$k} = $v if $k eq '_column' || $k =~ /asset/i;
                    }
                }
                \%a;
            } @{ $d->{1140} }
        ];
        $d->{1135} ||= [
            map {
                my %a;
                if ($_) {
                    while ( my ( $k, $v ) = each %$_ ) {
                        $a{$k} = $v if $k eq '_column' || $k =~ /loss/i;
                    }
                }
                \%a;
            } @{ $d->{1140} }
        ];
    }
    else {
        my $a = $d->{1140} ||= [ {} ];
        foreach (qw(1105 1122 1131 1135)) {
            my $t = $d->{$_} or next;
            my ( $kk, $match );
            if ( $_ == 1105 ) {
                $match = qr/diversity/i;
                $kk    = 'Diversity allowance between level exit and GSP Group';
            }
            elsif ( $_ == 1122 ) {
                $match = qr/simultaneous/i;
                $kk    = 'System simultaneous maximum load kW';
            }
            elsif ( $_ == 1131 ) {
                $match = qr/Assets/i;
                $kk    = 'Assets in CDCM model';
            }
            elsif ( $_ == 1135 ) {
                $match = qr/Loss/i;
                $kk    = 'Loss adjustment factor to transmission';
            }
            else {
                next;
            }
            for ( my $c = 1 ; $c < @$t ; ++$c ) {
                while ( my ( $k, $v ) = each %{ $t->[$c] } ) {
                    if ( $k eq '_column' ) { $a->[$c]{$k} ||= $v; }
                    else {
                        $a->[$c]{$kk} ||= $v;
                    }
                }
            }
        }
    }

    if ( $d->{1194} ) {
        my ( $key1191, $key1192, $key1194 ) = map {
            ( grep { !/^_/ } keys %{ $d->{$_}[1] } )[0]
        } qw(1191 1192 1194);
        $d->{1191}[4]{$key1191} =
          $d->{1194}[3]{$key1194};
        $d->{1192}[4]{$key1192} =
          $d->{1194}[1]{$key1194};
    }

    if (   $d->{1192} && $d->{1192}[5]
        || $d->{1192}[4] && $d->{1192}[4]{_column} )
    {
        my ( $key1191, $key1192 ) = map {
            ( grep { !/^_/ } keys %{ $d->{$_}[1] } )[0]
        } qw(1191 1192);
        my ($genRev) = splice @{ $d->{1192} }, 4, 1;
        splice @{ $d->{1191} }, 5, 0,
          {
            $key1191 => $genRev->{$key1192},
            $genRev->{_column} ? ( '_column' => $genRev->{_column} ) : ()
          };
    }

}

1;
