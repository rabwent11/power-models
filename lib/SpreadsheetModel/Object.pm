﻿package SpreadsheetModel::Object;

=head Copyright licence and disclaimer

Copyright 2008-2013 Franck Latrémolière, Reckon LLP and others.

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

use SpreadsheetModel::Label;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK =
  qw(_rewriteFormulae _shortName _shortNameRow _shortNameCol _numsort);
our %EXPORT_TAGS = ( '_util' => \@EXPORT_OK );

sub new {
    my $className = shift;
    die join ' ', 'Not an even number:', @_ if @_ % 2;
    my $self = { @_, debug => join ' line ', (caller)[ 1, 2 ] };
    unless ( defined $self->{name} ) {
        my @c = caller;
        $self->{name} = "Untitled, $c[1] line $c[2]";
    }
    bless $self, $className;
    my $error = $self->check;
    die "$self->{name} $self->{debug}: $error" if $error;
    push @{ $self->{appendTo} }, $self if $self->{appendTo};
    $self;
}

sub addForwardLink {
    my ( $self, $link ) = @_;
    $self->{forwardLinks}{ 0 + $link } = $link unless $self == $link;
}

sub requestForwardLinks {
    my ( $self, $wb, $ws, $rowref, $col ) = @_;
    goto &requestForwardTree if $wb->{forwardLinks} =~ /tree/i;
    return unless $self->{forwardLinks};
    my $saveCol    = $col - 1;
    my $linkFormat = $wb->getFormat('link');
    $ws->write( ++$$rowref, $saveCol, 'Used by:', $wb->getFormat('text') );
    my $saveRow = $$rowref;
    foreach ( values %{ $self->{forwardLinks} } ) {
        ++$$rowref;
        push @{ $_->{postWriteCalls}{$wb} }, sub {
            my ($me) = @_;
            if ( my $url = $me->wsUrl($wb) ) {
                $ws->write_url( ++$saveRow, $saveCol, $url,
                    "→ $me->{name}", $linkFormat );
            }
        };
    }
}

sub requestForwardTree {
    my ( $self, $wb, $ws, $rowref, $col ) = @_;
    return unless $self->{forwardLinks};
    my $saveCol    = $col - 1;
    my $linkFormat = $wb->getFormat('link');
    my $textFormat = $wb->getFormat('text');
    $ws->write( ++$$rowref, $saveCol, 'Used by:', $textFormat );
    my $masterPrefix = ' ';
    my %map          = %{ $self->{forwardLinks} };
    my @next         = values %map;
    my $saveRow      = $$rowref;

    while (@next) {
        my $prefix = $masterPrefix = '→' . $masterPrefix;
        my @current = @next;
        @next = ();
        foreach (@current) {
            ++$$rowref;
            push @{ $_->{postWriteCalls}{$wb} }, sub {
                my ($me) = @_;
                if ( my $url = $me->wsUrl($wb) ) {
                    $ws->write_url( ++$saveRow, $saveCol, $url,
                        "$prefix$me->{name}", $linkFormat );
                }
            };
            push @next, grep {
                if ( exists $map{ 0 + $_ } ) {
                    ();
                }
                else {
                    undef $map{ 0 + $_ };
                    1;
                }
            } values %{ $_->{forwardLinks} } if $_->{forwardLinks};
        }
    }
}

sub check {
    'I do not know what I am';
}

sub objectType {
    'Other';
}

sub populateCore {    #   $_[0]{core}{INCOMPLETE} = 1;
}

sub getCore {
    my ($self) = @_;
    return $self->{core} if $self->{core};
    $self->{core} = bless { name => "$self->{name}" }, ref $self;
    $self->{core}{$_} =
        UNIVERSAL::can( $self->{$_}, 'getCore' ) ? $self->{$_}->getCore
      : ref $self->{$_} eq 'ARRAY' ? $self->{$_}
      : "$self->{$_}"
      foreach grep { defined $self->{$_}; } qw(defaultFormat rows cols);
    $self->populateCore;
    $self->{core};
}

sub wsWrite {
    warn "$_->{name} cannot be written to a spreadsheet";
}

sub htmlWrite {
    my ( $self, $hb, $hs ) = @_;
    return $self->{$hb} if $self->{$hb};
    my $id = sprintf 'x%x', $self;
    $self->{$hb} = [
        $hs->(
            [
                fieldset => [
                    [ legend => "$self->{name} $self->{debug}" ],
                    $self->htmlDescribe( $hb, $hs )
                ],
                id => $id
            ]
        ) => $id
    ];
}

sub htmlDescribe {
    [ div => "No information available for $_[0]{name}" ], [ p => ref $_[0] ];
}

sub addTableNumber {    # prohibitedTableNumbers is a bad arrangement
    my ( $self, $wb, $ws ) = @_;
    return '' if $self->{name} =~ /^[0-9]+[a-z]*\.\s/;
    if ( !$ws->{sheetNumber} ) {
        do { $ws->{sheetNumber} = ++$wb->{lastSheetNumber} }
          while $wb->{prohibitedSheetNumberRegex}
          && $ws->{sheetNumber} =~ $wb->{prohibitedSheetNumberRegex};
    }
    my $numlet = $self->{number};
    unless ($numlet) {
        do {
            $numlet =
              ( $ws->{lastTableNumber} += ( $ws->{tableNumberIncrement} || 1 ) )
              + 100 * $ws->{sheetNumber};
          } while $wb->{prohibitedTableNumbers}
          && grep { $_ eq $numlet; } @{ $wb->{prohibitedTableNumbers} };
        ++$wb->{lastSheetNumber} unless $numlet % 100;
        die 'Non-sequential table numbers: '
          . "trying to assign $numlet to $self->{name} $self->{debug}"
          . " after $wb->{highestAutoTableNumber} had been assigned."
          if $wb->{highestAutoTableNumber}
          && $numlet < $wb->{highestAutoTableNumber};
        $wb->{highestAutoTableNumber} = $numlet;
    }
    $numlet .= '. ';
    $self->{name} =
      new SpreadsheetModel::Label( $numlet . $self->{name}, $self->{name} );
    $numlet;
}

sub splitLines {
    my ($x) = @_;
    return unless defined $x;
    return '' if $x eq '';
    return map { splitLines($_) } @$x if ref $x eq 'ARRAY';
    split /\n/, $x;
}

sub _shortName {
    my ($self) = @_;
    return $self->shortName if UNIVERSAL::can( $self, 'shortName' );
    my @self = split /\n/, $self;
    pop @self;
}

sub objectShortName {
    _shortName $_[0]{name};
}

sub _shortNameCol {
    local $_ = _shortName @_;
    tr/\t/\n/;
    $_;
}

sub _shortNameRow {
    local $_ = _shortName @_;
    tr/\t/ /;
    $_;
}

sub _numsort {
    local $_ = $_[0];
    return $_ unless /^([0-9]+)/;
    return $1 < 10 ? "0$_" : $_;
}

sub _rewriteFormulae {
    my ( $formulaListRef, $argumentHashListRef ) = @_;
    my @args;
    foreach my $i ( 0 .. $#$formulaListRef ) {
        foreach my $ph (
            sort {
                ( index $formulaListRef->[$i], $a )
                  <=> ( index $formulaListRef->[$i], $b )
            }
            grep {
                     $formulaListRef->[$i] =~ /Special/
                  || $formulaListRef->[$i] =~ /\b$_\b/
            }
            sort keys %{ $argumentHashListRef->[$i] }
          )
        {
            my $ar = $argumentHashListRef->[$i]{$ph};
            my ($n) = grep { $args[$_] == $ar } 0 .. $#args;
            if ( defined $n ) {
                ++$n;
            }
            else {
                push @args, $ar;
                $n = @args;
            }
            $formulaListRef->[$i] =~ s/$ph\b/x$n/;
        }
    }
    map { die $_ if /I[UV]/i } @$formulaListRef;
    @args;
}

1;
