﻿package SpreadsheetModel::ExportGraphviz;

=head Copyright licence and disclaimer

Copyright 2008-2013 Reckon LLP and others. All rights reserved.

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

# 'DYLD_INSERT_LIBRARIES=/usr/X11/lib/libpixman-1.0.dylib dot'
# '/Applications/Graphviz.app/Contents/MacOS/dot'
# '/usr/local/bin/dot'
my $dotCommandLine = 'dot';

sub writeGraphs {    # $logger->{objects} is a good $objectList
    my ( $objectList, $wbook, $pathPrefix ) = @_;
    $pathPrefix = '' unless defined $pathPrefix;
    my $obi = 0;
    my @sheets;
    my @sheetSubgraph;
    my @sheetName;
    foreach (@$objectList) {
        if ( $_->{name} =~ /^([0-9]+)([0-9]{2}|[a-z]+)\./ ) {
            push @{ $sheets[$1] }, $_;
            $_->{dotSheet} = $1;
            $sheetSubgraph[$1] = $_->{location}
              if $_->{location} && $wbook->{ $_->{location} };
            $sheetSubgraph[$1] ||= "cluster$1";
            $sheetName[$1] ||= $_->{$wbook}{worksheet}->get_name();
        }
    }

    my @dots;

    push @dots,
      join "\n",
      'digraph g {',
      'graph [rankdir=LR, size="16,10.5", concentrate=true, nodesep="0.2", '
      . 'ranksep="0.4",fontname="verdanab", fontsize="24", fontcolor="#666666"];',
      'node [label="\\N",shape=ellipse, style=filled, fontname=verdana, '
      . 'color="#0066cc", fillcolor=white, fontcolor=black, fontsize="20"];',
      'edge [arrowtail=none, fontname=verdana, color="#ff6633", '
      . 'fontcolor="#99b3cc", fontsize=18, style="setlinewidth(3)", arrowsize="2"];',
      (
        map {
            $sheets[$_]
              ? (
                "subgraph $sheetSubgraph[$_] {",
                qq%label="$sheetName[$_]";%,
                (
                    map {
                        _dotLabel(
                            $_->{dotName} =
                              't' . ++$obi,
                            $_->{name},
                            ref $_ eq 'SpreadsheetModel::Dataset'
                            ? ( rect => '#ccffff' )
                            : ref $_ eq 'SpreadsheetModel::Constant'
                            ? ( rect => '#e9e9e9' )
                            : ( Mrecord => '#ffffcc' )
                        );
                    } @{ $sheets[$_] }
                ),
                '}'
              )
              : ()
        } 0 .. $#sheets
      ),
      (
        map {
            my $ob = $_;
            $ob->{sourceLines}
              ? map {
                $_->{usedIn}[ $ob->{dotSheet} ] = 1;
                $_->{dotName}  ||= 'z' . ( 0 + $_ );
                $ob->{dotName} ||= 'z' . ( 0 + $ob );
                "$_->{dotName} -> $ob->{dotName};"
              } map {
                !$_->{sources}
                  || $#{ $_->{sources} }
                  || $_->{cols} != $_->{sources}[0]{cols}
                  || $_->{rows} != $_->{sources}[0]{rows}
                  ? $_
                  : $_->{sources}[0]
              } map {
                ref $_ eq 'SpreadsheetModel::View' ? $_->{sources}[0] : $_;
              } @{ $ob->{sourceLines} }
              : ();
          } grep {
            $_->isa('SpreadsheetModel::Dataset')
              || $_->isa('SpreadsheetModel::Columnset')
          } @$objectList
      ),
      '}';

    foreach my $shno ( grep { !$_ || $sheets[$_] } 0 .. $#sheets ) {
        my $graphTitle =
          $sheets[$shno] ? "$shno. $sheetName[$shno]" : 'Overview';
        push @dots,
          join "\n", "digraph g$shno {",
          'graph [rankdir=TD, size="10.5,8", concentrate=true, nodesep="0.2", '
          . qq%ranksep="0.4", fontname="verdanab", fontsize="32", fontcolor="#666666", label="$graphTitle"];%,
          'node [label="\\N",shape=ellipse, style=filled, fontname=verdana,'
          . ' color="#0066cc", fillcolor=white, fontcolor=black, fontsize="32"];',
          'edge [arrowtail=none, fontname=verdana, color="#ff6633", '
          . 'fontcolor="#99b3cc", fontsize=18, style="setlinewidth(3)", arrowsize="2"];',
          (
            map {
                   !$sheets[$_] ? ()
                  : $_ != $shno && $sheetSubgraph[$_] =~ /^cluster/
                  ? _dotLabel( "s$_", $sheetName[$_], ellipse => '#ffffff' )
                  : (
                    "subgraph $sheetSubgraph[$_] {",
                    'label="";',    # qq%label="$sheetName[$_]";%,
                    (
                        map {
                            _dotLabel( $_->{dotName}, $_->{name},
                                ref $_ eq 'SpreadsheetModel::Dataset'
                                ? ( rect => '#ccccff' )
                                : ref $_ eq 'SpreadsheetModel::Constant'
                                ? ( rect => '#cccccc' )
                                : ( Mrecord => '#ffffcc' ) );
                          } $_ == $shno
                        ? @{ $sheets[$_] }
                        : grep { $_->{usedIn}[$shno] } @{ $sheets[$_] }
                    ),
                    '}'
                  )
            } 0 .. $#sheets
          ),
          (
            map {
                my $obdn =
                  (      $_->{dotSheet} == $shno
                      || $sheetSubgraph[ $_->{dotSheet} ] !~ /^cluster/ )
                  ? $_->{dotName}
                  : "s$_->{dotSheet}";
                my $ob = $_;
                $ob->{sourceLines}
                  ? map {
                         !defined $_->{dotSheet}
                      || !$_->{usedIn}[$shno] && $obdn !~ /^s/ ? ()
                      : $_->{dotSheet} == $shno ? "$_->{dotName} -> $obdn;"
                      : $sheetSubgraph[ $_->{dotSheet} ] !~ /^cluster/ ? (
                        $_->{usedIn}[$shno] && $ob->{dotSheet} == $shno
                        ? "$_->{dotName} -> $obdn;"
                        : ()
                      )
                      : "s$_->{dotSheet}" eq $obdn ? ()
                      : "s$_->{dotSheet} -> $obdn;"
                  } map {
                    !$_->{sources}
                      || $#{ $_->{sources} }
                      || $_->{cols} != $_->{sources}[0]{cols}
                      || $_->{rows} != $_->{sources}[0]{rows}
                      ? $_
                      : $_->{sources}[0]
                  } map {
                    ref $_ eq 'SpreadsheetModel::View' ? $_->{sources}[0] : $_;
                  } @{ $ob->{sourceLines} }
                  : ();
              } grep {
                $_->isa('SpreadsheetModel::Dataset')
                  || $_->isa('SpreadsheetModel::Columnset')
              } @$objectList
          ),
          '}';
    }

    open my $hh, '>', $pathPrefix . 'index.html';
    binmode $hh, ':utf8';
    my $prefix = $pathPrefix;
    $prefix =~ s#^.*/##s;
    foreach ( 0 .. $#dots ) {
        open my $dh, '>', "$pathPrefix$_.dot";
        binmode $dh, ':utf8';
        print $dh $dots[$_];
        close $dh;
        `$dotCommandLine -Tpdf -o '$pathPrefix$_.pdf' '$pathPrefix$_.dot'`;
        $dots[$_] =~ s/size="[0-9\.]*, *[0-9\.]*"/size="6,4"/;
        open $dh, "| $dotCommandLine -Tpng -o '$pathPrefix$_.png'";
        binmode $dh, ':utf8';
        print $dh $dots[$_];
        close $dh;
        my ($title) = ( $dots[$_] =~ /label="(.*?)"/ );
        $title ||= 'Graph';
        print $hh "<p><strong>$title</strong></p>",
          qq%<p><a href="$prefix$_.pdf">%,
          qq%<img src="$prefix$_.png" alt="graph $_" />%,
          '<br />PDF version of the above graph</a></p><hr />';
    }
    close $hh;

}

sub _dotLabel {
    my ( $o, $name, $shape, $fillcolour ) = @_;
    $name =~ s/"/'/g;
    1 while $name =~ s/([^\\]{15,}?) (.{12,})/$1\\n$2/;
    qq#$o [label="$name", shape="$shape", fillcolor="$fillcolour"];#;
}

1;
