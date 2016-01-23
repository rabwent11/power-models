﻿package SpreadsheetModel::Chart;

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

require SpreadsheetModel::Object;
our @ISA = qw(SpreadsheetModel::Object);
use Spreadsheet::WriteExcel::Utility;

sub objectType {
    'Chart';
}

sub check {
    my ($self) = @_;
    return
        "Broken chart $self->{name} $self->{debug}: instructions is "
      . ( ref $self->{instructions} )
      . ' but must be ARRAY'
      unless ref $self->{instructions} eq 'ARRAY';
    $self->{height} ||= 288;
    $self->{width}  ||= 480;
    return;
}

sub wsUrl {
    my ( $self, $wb ) = @_;
    return unless $self->{$wb};
    my ( $wo, $ro, $co ) = @{ $self->{$wb} }{qw(worksheet row col)};
    my $ce = xl_rowcol_to_cell( $ro, $co );
    my $wn =
        $wo
      ? $wo->get_name
      : die( join "No worksheet for $self->{name}" );
    "internal:'$wn'!$ce";
}

sub applyInstructions {
    my ( $self, $chart, $wb, $ws, $instructions ) = @_;
    my @instructions = @$instructions;
    while (@instructions) {
        my ( $verb, $args ) = splice @instructions, 0, 2;
        if ( $verb eq 'combine' ) {
            my %a = @$args;
            my $i = delete $a{instructions};
            my $c = $wb->add_chart( %a, embedded => 1 );
            $self->applyInstructions( $c, $wb, $ws, $i );
            $chart->combine($c);
            next;
        }
        if ( $verb eq 'add_series' ) {
            my $series = $args;
            if ( ref $args eq 'ARRAY' ) {
                $series = shift @$args;
            }
            else {
                $args = [];
            }
            if ( UNIVERSAL::isa( $series, 'SpreadsheetModel::Dataset' )
                and !$series->{rows} && $series->{cols}
                || $series->{rows}   && !$series->{cols} )
            {
                push @{ $self->{sourceLines} }, $series
                  unless $self->{sourceLines} && grep { $_ == $series }
                  @{ $self->{sourceLines} };
                my ( $w2, $r2, $c2 ) =
                  $series->wsWrite( $wb, $ws, undef, undef, 1 );
                $w2 = "'" . $w2->get_name . "'!";
                my $r3 = $r2;
                my $c3 = $c2;
                if ( $series->{cols} ) {
                    if (
                        UNIVERSAL::isa(
                            $series->{location}, 'SpreadsheetModel::CalcBlock'
                        )
                      )
                    {
                        $r3 = $series->{location}{items}[0]{$wb}{row};
                    }
                    --$r3;
                }
                else {
                    if (
                        UNIVERSAL::isa(
                            $series->{location}, 'SpreadsheetModel::Columnset'
                        )
                      )
                    {
                        $c3 = $series->{location}{columns}[0]{$wb}{col};
                    }
                    --$c3;
                }
                unshift @$args,
                  name       => $series->objectShortName,
                  categories => '='
                  . $w2
                  . xl_rowcol_to_cell(
                    $r3 + ( $self->{ignore_top}  || 0 ),
                    $c3 + ( $self->{ignore_left} || 0 ),
                    1, 1,
                  )
                  . ':'
                  . xl_rowcol_to_cell(
                    $r3 + $series->lastRow - ( $self->{ignore_bottom} || 0 ),
                    $c3 + $series->lastCol - ( $self->{ignore_right}  || 0 ),
                    1,
                    1,
                  ),
                  values => '='
                  . $w2
                  . xl_rowcol_to_cell(
                    $r2 + ( $self->{ignore_top}  || 0 ),
                    $c2 + ( $self->{ignore_left} || 0 ),
                    1, 1,
                  )
                  . ':'
                  . xl_rowcol_to_cell(
                    $r2 + $series->lastRow - ( $self->{ignore_bottom} || 0 ),
                    $c2 + $series->lastCol - ( $self->{ignore_right}  || 0 ),
                    1,
                    1,
                  );
            }
            elsif (ref $series eq 'ARRAY'
                && UNIVERSAL::isa( $series->[0], 'SpreadsheetModel::Dataset' )
                && UNIVERSAL::isa( $series->[1], 'SpreadsheetModel::Dataset' )
                and !$series->[0]{rows}
                && !$series->[1]{rows}
                && $series->[0]{cols}
                && $series->[1]{cols}
                && $series->[0]{cols} == $series->[1]{cols}
                || !$series->[0]{cols}
                && !$series->[1]{cols}
                && $series->[0]{rows}
                && $series->[1]{rows}
                && $series->[0]{rows} == $series->[1]{rows} )
            {
                foreach my $d (@$series) {
                    push @{ $self->{sourceLines} }, $d
                      unless $self->{sourceLines} && grep { $_ == $d }
                      @{ $self->{sourceLines} };
                }
                my ( $w2, $r2, $c2 ) =
                  $series->[1]->wsWrite( $wb, $ws, undef, undef, 1 );
                $w2 = "'" . $w2->get_name . "'!";
                my ( $w3, $r3, $c3 ) =
                  $series->[0]->wsWrite( $wb, $ws, undef, undef, 1 );
                $w3 = "'" . $w3->get_name . "'!";
                unshift @$args,
                  name       => $series->[1]->objectShortName,
                  categories => '='
                  . $w3
                  . xl_rowcol_to_cell(
                    $r3 + ( $self->{ignore_top}  || 0 ),
                    $c3 + ( $self->{ignore_left} || 0 ),
                    1, 1,
                  )
                  . ':'
                  . xl_rowcol_to_cell(
                    $r3 + $series->[0]->lastRow -
                      ( $self->{ignore_bottom} || 0 ),
                    $c3 + $series->[0]->lastCol -
                      ( $self->{ignore_right} || 0 ),
                    1,
                    1,
                  ),
                  values => '='
                  . $w2
                  . xl_rowcol_to_cell(
                    $r2 + ( $self->{ignore_top}  || 0 ),
                    $c2 + ( $self->{ignore_left} || 0 ),
                    1, 1,
                  )
                  . ':'
                  . xl_rowcol_to_cell(
                    $r2 + $series->[1]->lastRow -
                      ( $self->{ignore_bottom} || 0 ),
                    $c2 + $series->[1]->lastCol -
                      ( $self->{ignore_right} || 0 ),
                    1,
                    1,
                  );
            }
            else {
                warn "Something has probably gone wrong with @$args";
                next;
            }
        }
        $chart->$verb(@$args);
    }
}

sub wsWrite {
    my ( $self, $wb, $ws, $row, $col ) = @_;
    return if $self->{$wb};
    my $chart = $wb->add_chart(
        %$self,
        embedded => $ws ? 1 : 0,
        name => $self->objectShortName,
    );
    $self->applyInstructions( $chart, $wb, $ws, $self->{instructions} );

    if ($ws) {
        ( $row, $col ) = ( ( $ws->{nextFree} ||= -1 ) + 1, 0 )
          unless defined $row && defined $col;

        if ( $self->{name} ) {
            $ws->write( $row, $col, "$self->{name}", $wb->getFormat('notes') );
            $ws->set_row( $row, 21 );
            ++$row;
        }

        if ( $self->{lines}
            or !( $wb->{noLinks} && $wb->{noLinks} == 1 )
            and $self->{name} && $self->{sourceLines} )
        {
            my $hideFormulas = $wb->{noLinks} && $self->{sourceLines};
            my $textFormat   = $wb->getFormat('text');
            my $linkFormat   = $wb->getFormat('link');
            my $xc           = 0;
            foreach (
                $self->{lines} ? @{ $self->{lines} } : (),
                !( $wb->{noLinks} && $wb->{noLinks} == 1 )
                && $self->{sourceLines} && @{ $self->{sourceLines} }
                ? ( 'Data sources:', @{ $self->{sourceLines} } )
                : ()
              )
            {
                if ( UNIVERSAL::isa( $_, 'SpreadsheetModel::Object' ) ) {
                    my $na = 'x' . ( ++$xc ) . " = $_->{name}";
                    if ( my $url = $_->wsUrl($wb) ) {
                        $ws->set_row( $row, undef, undef, 1, 1 )
                          if $hideFormulas;
                        $ws->write_url( $row++, $col, $url, $na, $linkFormat );
                        (
                            $_->{location}
                              && UNIVERSAL::isa( $_->{location},
                                'SpreadsheetModel::Columnset' )
                            ? $_->{location}
                            : $_
                          )->addForwardLink($self)
                          if $wb->{findForwardLinks};
                    }
                    else {
                        $ws->set_row( $row, undef, undef, 1, 1 )
                          if $hideFormulas;
                        $ws->write_string( $row++, $col, $na, $textFormat );
                    }
                }
                elsif (/^(https?|mailto:)/) {
                    $ws->set_row( $row, undef, undef, 1, 1 )
                      if $hideFormulas;
                    $ws->write_url( $row++, $col, "$_", "$_", $linkFormat );
                }
                else {
                    $ws->set_row( $row, undef, undef, 1, 1 )
                      if $hideFormulas;
                    $ws->write_string( $row++, $col, "$_", $textFormat );
                }
            }
            $ws->set_row( $row, undef, undef, undef, 0, 0, 1 )
              if $hideFormulas;
        }

        ++$row;
        $ws->set_row( $row, $self->{height} * 0.75 );
        $ws->insert_chart(
            $row, $col + 1, $chart, 0, 0,
            $self->{width} / 480.0,
            $self->{height} / 288.0
        );
        $row += 2;
        $ws->{nextFree} = $row unless $ws->{nextFree} > $row;
    }
    else {    # Chartsheet
        $chart->protect();
    }

}

1;
