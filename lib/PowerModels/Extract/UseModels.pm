﻿package PowerModels::Extract::UseModels;

=head Copyright licence and disclaimer

Copyright 2011-2017 Franck Latrémolière and others. All rights reserved.

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
use File::Glob qw(bsd_glob);
use File::Spec::Functions qw(abs2rel rel2abs);

use constant { C_HOMES => 0, };

sub useModels {

    my $self = shift;

    my ( @writerAndParserOptions, $fillSettings, $postProcessor, $executor,
        @files );

    foreach (@_) {
        if (/^-+single/is) {
            $executor = 0;
            next;
        }
        if (/^-+([0-9]*)([tp])?$/is) {
            unless ($executor) {
                if ( $2 ? $2 eq 't' : $^O =~ /win32/i ) {
                    require PowerModels::CLI::ExecutorThread;
                    $executor = PowerModels::CLI::ExecutorThread->new;
                }
                else {
                    require PowerModels::CLI::ExecutorFork;
                    $executor = PowerModels::CLI::ExecutorFork->new;
                }
            }
            $executor->setThreads($1) if $1;
            next;
        }
        if (/^-+(re-?build.*)/i) {
            require PowerModels::Extract::Rebuild;
            @writerAndParserOptions =
              PowerModels::Extract::Rebuild::rebuildWriter( $1, $self );
            next;
        }
        if (/^-+(ya?ml.*)/i) {
            require PowerModels::Extract::Yaml;
            @writerAndParserOptions = PowerModels::Extract::Yaml::ymlWriter($1);
            next;
        }
        if (/^-+rules/i) {
            require PowerModels::Rules::FromWorkbook;
            @writerAndParserOptions =
              PowerModels::Rules::FromWorkbook::rulesWriter();
            next;
        }
        if (/^-+jbz/i) {
            require PowerModels::Rules::FromWorkbook;
            @writerAndParserOptions =
              PowerModels::Rules::FromWorkbook::jbzWriter();
            next;
        }
        if (/^-+autocheck=?(.+)?/i) {
            require PowerModels::Extract::Autocheck;
            @writerAndParserOptions =
              PowerModels::Extract::Autocheck->new( $self->[C_HOMES], $1 )
              ->writerAndParserOptions;
            next;
        }
        if (/^-+outputs?=?(.+)?/i) {
            require PowerModels::Extract::SelectedTablesJson;
            @writerAndParserOptions =
              PowerModels::Extract::SelectedTablesJson->new($1)
              ->writerAndParserOptions;
            next;
        }
        if (/^-+sqlite3?(=.*)?$/i) {
            my %settings;
            if ( my $wantedSheet = $1 ) {
                $wantedSheet =~ s/^=//;
                $settings{sheetFilter} = sub { $_[0]{Name} eq $wantedSheet; };
            }
            require PowerModels::Database::Importer;
            @writerAndParserOptions =
              PowerModels::Database::Importer::databaseWriter( \%settings );
            next;
        }
        if (/^-+prune=(.*)$/i) {
            unless (@writerAndParserOptions) {
                require PowerModels::Database::Importer;
                @writerAndParserOptions =
                  PowerModels::Database::Importer::databaseWriter( {} );
            }
            @writerAndParserOptions->( undef, $1 );
            next;
        }
        if (/^-+xls$/i) {
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::xlsWriter();
            next;
        }
        if (/^-+flat/i) {
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::xlsFlattener();
            next;
        }
        if (/^-+(tsv|txt|csv)$/i) {
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::tsvDumper($1);
            next;
        }
        if (/^-+tall(csv)?$/i) {
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::tallDumper( $1 || 'xls' );
            next;
        }
        if (/^-+cat$/i) {
            $executor = 0;
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::tsvDumper( \*STDOUT );
            next;
        }
        if (/^-+split$/i) {
            require PowerModels::Extract::Dumpers;
            @writerAndParserOptions =
              PowerModels::Extract::Dumpers::xlsSplitter();
            next;
        }
        if (/^-+(calc|convert.*)/i) {
            $fillSettings = $1;
            next;
        }

        push @files, -f $_ ? $_ : grep { -f $_; } bsd_glob($_);

    }

    unless ( defined $executor ) {
        if ( $^O !~ /win32/i
            && eval 'require PowerModels::CLI::ExecutorFork' )
        {
            $executor = PowerModels::CLI::ExecutorFork->new;
        }
        elsif ( eval 'require PowerModels::CLI::ExecutorThread' ) {
            $executor = PowerModels::CLI::ExecutorThread->new;
        }
        else {
            warn "No multi-threading: $@";
        }
    }

    ( $postProcessor ||=
          $self->makePostProcessor( $fillSettings, @writerAndParserOptions ) )
      ->( $_, $executor )
      foreach @files;

    if ($executor) {
        if ( my @errors = $executor->complete ) {
            my $wrong = (
                  @errors > 1
                ? @errors . " things have"
                : 'Something has'
            ) . ' gone wrong.';
            warn "$wrong\n";
            warn sprintf( "%3d❗️ %s\n", $_ + 1, $errors[$_][0] )
              foreach 0 .. $#errors;
        }
    }

}

sub makePostProcessor {

    my ( $self, $processSettings, @writerAndParserOptions, ) = @_;

    my ( $calc_mainprocess, $calc_ownthread, $calcWorker );
    if ( $processSettings && $processSettings =~ /calc|convert/i ) {

        if ( $^O =~ /win32/i ) {

            # Control Microsoft Excel (not Excel Mobile) under Windows.
            # Each calculator runs in its own thread, run synchronously.
            # (Loading Win32::OLE in the mother thread causes a crash.)
            # It would have been better to set up a single worker thread
            # and some queues to handle Win32::OLE calculations.

            if ( $processSettings =~ /calc/ ) {
                $calc_ownthread = sub {
                    my ($inname) = @_;
                    my $inpath = $inname;
                    $inpath =~ s/\.(xls.?)$/-$$.$1/i;
                    rename $inname, $inpath;
                    require Win32::OLE;
                    if ( my $excelApp =
                           Win32::OLE->GetActiveObject('Excel.Application')
                        || Win32::OLE->new( 'Excel.Application', 'Quit' ) )
                    {
                        my $excelWorkbooks;
                        $excelWorkbooks = $excelApp->Workbooks
                          until $excelWorkbooks;
                        my $excelWorkbook;
                        $excelWorkbook = $excelWorkbooks->Open($inpath)
                          until $excelWorkbook;
                        $excelWorkbook->Save;
                        warn 'Waiting for Excel' until $excelWorkbook->Saved;
                        $excelWorkbook->Close;
                        $excelWorkbook->Dispose;
                    }
                    else {
                        warn 'Cannot find Microsoft Excel';
                    }
                    rename $inpath, $inname
                      or die "rename $inpath, $inname: $! in " . `pwd`;
                    $inname;
                };
            }
            else {
                my @convertIncantation = ( FileFormat => 39 );
                my $convertExtension = '.xls';
                if ( $processSettings =~ /xlsx/i ) {
                    @convertIncantation = ();
                    $convertExtension   = '.xlsx';
                }
                $calc_ownthread = sub {
                    my ($inname) = @_;
                    my $inpath   = $inname;
                    my $outpath  = $inpath;

                    $outpath =~ s/\.xls.?$/$convertExtension/i;
                    my $outname = $outpath;
                    s/\.(xls.?)$/-$$.$1/i foreach $inpath, $outpath;
                    rename $inname, $inpath;
                    require Win32::OLE;
                    if ( my $excelApp =
                           Win32::OLE->GetActiveObject('Excel.Application')
                        || Win32::OLE->new( 'Excel.Application', 'Quit' ) )
                    {
                        my $excelWorkbooks;
                        $excelWorkbooks = $excelApp->Workbooks
                          until $excelWorkbooks;
                        my $excelWorkbook;
                        $excelWorkbook = $excelWorkbooks->Open($inpath)
                          until $excelWorkbook;
                        $excelWorkbook->SaveAs(
                            { FileName => $outpath, @convertIncantation } );
                        warn 'Waiting for Excel' until $excelWorkbook->Saved;
                        $excelWorkbook->Close;
                        $excelWorkbook->Dispose;
                    }
                    else {
                        warn 'Cannot find Microsoft Excel';
                    }
                    rename $inpath,  $inname;
                    rename $outpath, $outname
                      or die "rename $outpath, $outname: $! in " . `pwd`;
                    $outname;
                };
            }
        }

        elsif (`which osascript`) {

            # Control Microsoft Excel under Apple macOS.

            if ( $processSettings =~ /calc/ ) {
                $calc_mainprocess = sub {
                    my ($inname) = @_;
                    my $inpath = $inname;
                    $inpath =~ s/\.(xls.?)$/-$$.$1/i;
                    rename $inname, $inpath;
                    open my $fh, '| osascript';
                    binmode $fh, ':utf8';
                    print $fh <<EOS;
tell application "Microsoft Excel"
	set theWorkbook to open workbook workbook file name POSIX file "$inpath"
	set calculate before save to true
	close theWorkbook saving yes
end tell
EOS
                    close $fh;
                    rename $inpath, $inname
                      or die "rename $inpath, $inname: $! in " . `pwd`;
                    $inname;
                };
            }
            else {
                my $convert          = ' file format Excel98to2004 file format';
                my $convertExtension = '.xls';
                if ( $processSettings =~ /xlsx/i ) {
                    $convert          = '';
                    $convertExtension = '.xlsx';
                }
                $calc_mainprocess = sub {
                    my ($inname) = @_;
                    my $inpath   = $inname;
                    my $outpath  = $inpath;
                    $outpath =~ s/\.xls.?$/$convertExtension/i;
                    my $outname = $outpath;
                    s/\.(xls.?)$/-$$.$1/i foreach $inpath, $outpath;
                    rename $inname, $inpath;
                    open my $fh, '| osascript';
                    binmode $fh, ':utf8';
                    print $fh <<EOS;
tell application "Microsoft Excel"
	set theWorkbook to open workbook workbook file name POSIX file "$inpath"
	set calculate before save to true
	set theFile to POSIX file "$outpath" as string
	save workbook as theWorkbook filename theFile$convert
	close active workbook saving no
end tell
EOS
                    close $fh;
                    rename $inpath,  $inname;
                    rename $outpath, $outname
                      or die "rename $outpath, $outname: $! in " . `pwd`;
                    $outname;
                };
            }
        }

        elsif (`which ssconvert`) {

            # Try to calculate workbooks using ssconvert

            warn 'Using ssconvert';
            $calcWorker = sub {
                my ($inname) = @_;
                my $inpath   = $inname;
                my $outpath  = $inpath;
                $outpath =~ s/\.xls.?$/\.xls/i;
                my $outname = abs2rel($outpath);
                s/\.(xls.?)$/-$$.$1/i foreach $inpath, $outpath;
                rename $inname, $inpath;
                my @b = ( $inpath, $outpath );
                s/'/'"'"'/g foreach @b;
                system qq%ssconvert --recalc '$b[0]' '$b[1]' 2>/dev/null%;
                rename $inpath,  $inname;
                rename $outpath, $outname;
                $outname;
            };
        }

        else {
            warn 'No automatic calculation attempted';
        }

    }

    require Cwd;
    my $wd = Cwd::getcwd();

    sub {
        my ( $inFile, $executor ) = @_;
        my $absFile = rel2abs( $inFile, $wd );
        unless ( -f $absFile ) {
            warn "$absFile not found";
            return;
        }
        $absFile = $calc_mainprocess->($absFile) if $calc_mainprocess;
        $absFile =
          $INC{'threads.pm'}
          ? threads->new( $calc_ownthread, $absFile )->join
          : $calc_ownthread->($absFile)
          if $calc_ownthread;
        if ($executor) {
            $executor->run( __PACKAGE__, 'parseModel', $absFile,
                [ $calcWorker, @writerAndParserOptions ] );
        }
        else {
            __PACKAGE__->parseModel( $absFile, $calcWorker,
                @writerAndParserOptions );
        }
    };

}

sub parseModel {
    my ( undef, $workbookFile, $calcWorker, $writer, %parserOptions ) = @_;
    $workbookFile = $calcWorker->($workbookFile) if $calcWorker;
    my $workbookParseResults;
    eval {
        my $parserModule;
        my $formatter = 'PowerModels::Extract::UseModels::NoOp';
        if ( $workbookFile =~ /\.xls[xm]$/is ) {
            require Spreadsheet::ParseXLSX;
            $parserModule = 'Spreadsheet::ParseXLSX';
        }
        else {
            require Spreadsheet::ParseExcel;
            eval {    # NoOp produces warnings, the Japanese formatter does not
                require Spreadsheet::ParseExcel::FmtJapan;
                $formatter = Spreadsheet::ParseExcel::FmtJapan->new;
            };
            $parserModule = 'Spreadsheet::ParseExcel';
        }
        if ( my $setup = delete $parserOptions{Setup} ) {
            $setup->($workbookFile);
        }
        my $parser = $parserModule->new(%parserOptions);
        $workbookParseResults = $parser->parse( $workbookFile, $formatter );
    };
    warn "$@ for $workbookFile" if $@;
    if ($writer) {
        if ($workbookParseResults) {
            eval { $writer->( $workbookFile, $workbookParseResults ); };
            die "$@ for $workbookFile" if $@;
        }
        else {
            die "Cannot parse $workbookFile";
        }
    }
    0;
}

# Do-nothing cell content formatter for Spreadsheet::ParseExcel
package PowerModels::Extract::UseModels::NoOp;

our $AUTOLOAD;

sub AUTOLOAD {
    no strict 'refs';
    *{$AUTOLOAD} = sub { };
    return;
}

1;
