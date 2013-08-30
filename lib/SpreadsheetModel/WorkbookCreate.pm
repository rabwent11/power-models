package SpreadsheetModel::WorkbookCreate;

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
use SpreadsheetModel::Logger;
use File::Spec::Functions qw(catfile);

sub bgCreate {
    my ( $module, $fileName, @arguments ) = @_;
    my $pid = fork;
    return $pid, $fileName if $pid;
    $0 = "perl: $fileName";
    $module->create( $fileName, @arguments );
    exit 0 if defined $pid;

    # NB: if we do not want to rely on "exit", then do something like:
    #     $ENV{PATH} = '';
    #     eval { File::Temp::cleanup(); };
    #     exec '/bin/test';

    $pid;
}

sub create {
    my ( $module, $fileName, $optionsref ) = @_;
    my @optionArray = ref $optionsref eq 'ARRAY' ? @$optionsref : $optionsref;
    my @localTime = localtime;
    $module->fixName( $fileName, \@localTime );
    my $tmpDir;
	$tmpDir = '~$tmp-' . $$ unless $^O =~ /win32/i;
    mkdir $tmpDir and chmod 0770, $tmpDir if $tmpDir;
    open my $handle, '>', $tmpDir ? catfile( $tmpDir, $fileName ) : $fileName;
    my $wbook = $module->new($handle);
    $wbook->set_tempdir($tmpDir)
      if $tmpDir && $module !~ /xlsx/i;    # work around taint issue with IO::File
    $wbook->setFormats( $optionArray[0] );
    my @models;
    my $optionsColumns;
    my @allCoreNames;
    my %allClosures;
    my $forwardLinkFindingRun;
    my $multiModelSharing;

    if ( $#optionArray > 0 ) {
        $multiModelSharing = {};
        $_->{multiModelSharing} = $multiModelSharing foreach @optionArray;
    }

    foreach ( 0 .. $#optionArray ) {
        my $options = $optionArray[$_];
        $options->{optionsColumns} = $optionsColumns if $optionsColumns;
        my $modelCount = $_ ? ".$_" : '';
        $modelCount = '.' . ( 1 + $_ ) if @optionArray > 1;
        delete $options->{inputData} if $options->{oneSheet};
        my $model = $options->{PerlModule}->new(%$options);
        $forwardLinkFindingRun = $model if $options->{forwardLinks};
        $options->{revisionText} ||= '';
        0 and $wbook->{titlePrefix} ||= $options->{revisionText};
        $model->{localTime} = \@localTime;
        $SpreadsheetModel::ShowDimensions = $options->{showDimensions}
          if $options->{showDimensions};
        $options->{logger} =
          new SpreadsheetModel::Logger( name => 'List of data tables', );
        my @wsheetsAndClosures = $model->worksheetsAndClosures($wbook);
        my @wsheetNames =
          @wsheetsAndClosures[ grep { !( $_ % 2 ) } 0 .. $#wsheetsAndClosures ];
        $options->{wsheetNames} = [ map { $_ . $modelCount } @wsheetNames ];
        my %closure = @wsheetsAndClosures;
        my @frontSheets =
          grep { $closure{$_} } (
              $model->can('frontSheets')
            ? $model->frontSheets($wbook)
            : qw(Overview Index)
          );
        my %frontSheetHash = map { ( $_ => undef ); } @frontSheets;
        push @allCoreNames, @frontSheets,
          grep { !exists $frontSheetHash{$_} } @wsheetNames
          unless $_;
        $allClosures{ $_ . $modelCount } = $closure{$_}
          foreach grep { $closure{$_} } @allCoreNames;
    }
    my %wsheet;
    foreach my $cn (@allCoreNames) {
        foreach ( 0 .. $#optionArray ) {
            my $options = $optionArray[$_];
            my $modelCount = $_ ? ".$_" : '';
            $modelCount = '.' . ( 1 + $_ ) if @optionArray > 1;
            if ( $allClosures{ $cn . $modelCount } ) {
                my $ws;
                if ( ref $options->{oneSheet} ) { $ws = $options->{oneSheet}; }
                else {
                    $ws = $wbook->add_worksheet( $cn . $modelCount );
                    $ws->activate
                      if $options->{activeSheets}
                      && "$cn$modelCount" =~ /$options->{activeSheets}/;
                    $ws->fit_to_pages( 1, 0 );
                    $ws->set_header("&L&A&C$options->{revisionText}&R&P of &N");
                    $ws->set_footer("&F");
                    $ws->hide_gridlines(2);
                    $ws->protect( $options->{password} )
                      if $options->{protect}
                      && $cn ne 'Overview'
                      && $cn ne 'Index';
                    $options->{oneSheet} = $ws if $options->{oneSheet};
                }
                $wsheet{ $cn . $modelCount } = $ws;
            }
        }
    }
    $wbook->{$_} = $wsheet{$_} foreach keys %wsheet;
    foreach ( 0 .. $#optionArray ) {
        my $options = $optionArray[$_];
        my $modelCount = $_ ? ".$_" : '';
        $modelCount = '.' . ( 1 + $_ ) if @optionArray > 1;
        if ( $options->{inputData} ) {
            $wbook->{inputSheet} = $wsheet{ 'Input' . $modelCount }
              if $options->{inputData} =~ /inputSheet/;
            $wbook->{dataSheet} = $wsheet{ 'Input' . $modelCount }
              if $options->{inputData} =~ /dataSheet/;
        }

        if ($forwardLinkFindingRun) {
            open my $h2, '>', '/dev/null';
            my $wb2 = $module->new($h2);
            $wb2->setFormats($options);
            $wb2->{findForwardLinks} = 1;
            my %closures2 = $forwardLinkFindingRun->worksheetsAndClosures($wb2);
            $wb2->{$_} = $wb2->add_worksheet($_) foreach @allCoreNames;
            $closures2{$_}->( $wb2->{$_} )
              foreach grep { !/Overview|Index/i } @{ $options->{wsheetNames} };
            $wb2->close;
        }

        $wbook->{noData} = $options->{dataset} && !$options->{illustrative};
        $wbook->{$_} = $options->{$_}
          foreach grep { exists $options->{$_} }
          qw(copy debug forwardLinks logAll logger noLinks rowHeight validation);

        $allClosures{$_}->( $wsheet{$_} ) foreach @{ $options->{wsheetNames} };

        if ( $options->{ExportHtml} ) {
            require SpreadsheetModel::ExportHtml;
            my $dir = "$fileName-html$modelCount";
            mkdir $dir;
            chmod 0770, $dir;
            SpreadsheetModel::ExportHtml::writeHtml(
                $options->{logger}{objects}, "$dir/" );
        }

        if ( $options->{ExportGraphviz} ) {
            require SpreadsheetModel::ExportGraphviz;
            my $dir = "$fileName-graphs$modelCount";
            mkdir $dir;
            chmod 0770, $dir;
            SpreadsheetModel::ExportGraphviz::writeGraphs(
                $options->{logger}{objects},
                $wbook, "$dir/" );
        }

        if ( $options->{ExportYaml} || $options->{ExportPerl} ) {
            my @coreObj =
              map { UNIVERSAL::can( $_, 'getCore' ) ? $_->getCore : "$_"; }
              grep { defined $_ } @{ $options->{logger}{objects} };
            my $file = $fileName;
            $file =~ s/\.xlsx?$//i;
            $file .= "-dump$modelCount";
            if ( $options->{ExportYaml} ) {
                require YAML;
                open my $fh, '>', "$file.yaml";
                binmode $fh, ':utf8';
                print {$fh}
                  YAML::Dump(
                    { map { ( ref $_ ? $_->{name} : $_, $_ ); } @coreObj } );
            }
            if ( $options->{ExportPerl} ) {
                require Data::Dumper;
                open my $fh, '>', "$file.pl";
                print {$fh} Data::Dumper->new( \@coreObj )->Indent(1)->Names(
                    [
                        map {
                            my $n =
                              ref $coreObj[$_]
                              ? $coreObj[$_]{name}
                              : $coreObj[$_];
                            $n =~ s/[^a-z0-9]+/_/gi;
                            'VAR' . ( 1 + $_ ) . "_T$n";
                        } 0 .. $#coreObj
                    ]
                )->Dump;
            }
        }

    }

    $multiModelSharing->{finish}->()
      if $multiModelSharing && ref $multiModelSharing->{finish} eq 'CODE';

    $wbook->close;
	if ($tmpDir) {
	    rename catfile( $tmpDir, $fileName ), $fileName;
	    rmdir $tmpDir;
	}
}

sub writeColourCode {
    my ( $wbook, $wsheet ) = @_;
    $wsheet->write_string( 2, 2, 'Colour coding', $wbook->getFormat('thc') );
    $wsheet->write_string( 3, 2, 'Data input', $wbook->getFormat('0.000hard') );
    $wsheet->write_string(
        7, 2,
        'Unused cell in input data table',
        $wbook->getFormat('unused')
    );
    $wsheet->write_string( 6, 2, 'Calculation',
        $wbook->getFormat('0.000soft') );
    $wsheet->write_string( 5, 2, 'Copy data', $wbook->getFormat('0.000copy') );
    $wsheet->write_string(
        8, 2,
        'Unused cell in calculation table',
        $wbook->getFormat('unavailable')
    );
    $wsheet->write_string(
        4, 2,
        'Constant value',
        $wbook->getFormat('0.000con')
    );
    $wsheet->write_string( 9, 2, 'User notes', $wbook->getFormat('scribbles') );
}

1;