package SpreadsheetModel::Book::WorkbookCreate;

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
use SpreadsheetModel::Logger;
use File::Spec::Functions qw(catdir catfile splitpath);

sub create {

    my ( $module, $fileName, $instructions, $settings ) = @_;

    my @hazardousWaste;
    my @optionArray =
      ref $instructions eq 'ARRAY' ? @$instructions : $instructions;
    my @localTime   = localtime;
    my $streamMaker = $settings->{streamMaker};
    $streamMaker ||= sub {
        my ($finalFile) = @_;
        unless ($finalFile) {
            binmode STDOUT;
            return \*STDOUT;
        }
        my ( $tempFile, $afterClose, $tmpDir );
        if ( $^O !~ /win32/i ) {
            $tmpDir = '~$tmp-' . $$ . rand();
            $tmpDir = catdir( $settings->{folder}, $tmpDir )
              if $settings->{folder};
            mkdir $tmpDir or warn "Failed mkdir $tmpDir: $!";
            chmod 0770, $tmpDir;
            unless ( -d $tmpDir && -w _ ) {
                warn "Failed to create $tmpDir";
                undef $tmpDir;
            }
        }
        if ( defined $tmpDir ) {
            $tempFile =
              catfile( $tmpDir, ( splitpath($finalFile) )[2] );
            $afterClose = sub {
                rename $tempFile, $finalFile;
                rmdir $tmpDir or warn "rmdir $tmpDir: $!";
            };
        }
        else {
            my @split = splitpath($finalFile);
            $tempFile =
              catfile( $split[1], '~$tmp-' . $$ . rand() . '-' . $split[2] );
            $afterClose = sub {
                rename $tempFile, $finalFile;
            };
        }
        $tempFile, $afterClose, $finalFile;
    };

    ( my $fileOrHandle, my $afterClose, $fileName ) = $streamMaker->($fileName);
    my $wbook = $module->new($fileOrHandle);
    my @exports = grep { $settings->{$_} && /^Export/ } keys %$settings;
    my $exporter;
    if (@exports) {
        eval {
            require SpreadsheetModel::Export::Controller;
            $exporter =
              SpreadsheetModel::Export::Controller->new( $fileName, $wbook );
        };
        warn "@exports: $@" if $@;
    }

    $wbook->setFormats( $optionArray[0] );
    my @models;
    my ( %allClosures, @wsheetShowOrder, %wsheetActive, %wsheetPassword,
        %sheetDisplayName, @forwardLinkFindingRun, $multiModelSharing );

    foreach my $i ( 0 .. $#optionArray ) {
        if ( my $dataset = $optionArray[$i]{dataset} ) {
            if ( my $yaml = $dataset->{yaml} ) {
                require YAML;    # deferred parsing of YAML data
                my @parsed = YAML::Load($yaml);
                if ( @parsed > 1 ) {
                    foreach my $section (@parsed) {
                        while ( my ( $tab, $dat ) = each %$section ) {
                            next unless ref $dat eq 'ARRAY';
                            for ( my $col = 0 ; $col < @$dat ; ++$col ) {
                                my $cd = $dat->[$col];
                                next unless ref $cd eq 'HASH';
                                while ( my ( $row, $v ) = each %$cd ) {
                                    $dataset->{$tab}[$col]{$row} = $v;
                                }
                            }
                        }
                    }
                }
                else {
                    %$dataset = %{ $parsed[0] };
                }
            }
            if ( my $sourceNameMatches =
                $optionArray[$i]{dataset}{sourceModelsDatasetNameMatches} )
            {
                my $target = $optionArray[$i];
                while ( my ( $key, $sourceNameMatch ) =
                    each %$sourceNameMatches )
                {
                    foreach my $potentialSource (@optionArray) {
                        if (   $potentialSource != $target
                            && $potentialSource->{'~datasetName'}
                            && $potentialSource->{'~datasetName'} =~
                            /$sourceNameMatch/ )
                        {
                            push @{ $potentialSource->{requestsToSeeModel} },
                              sub {
                                $target->{sourceModels}{$key} = $_[0];
                              };
                            last;
                        }
                    }
                }
            }
            else {
                my @dataLayers =
                  grep { $_ }
                  $optionArray[$i]{illustrative}
                  ? { usePlaceholderData => $optionArray[$i]{illustrative}, }
                  : (), $optionArray[$i]{illustrative}
                  || $dataset && $dataset->{usePlaceholderData}
                  ? $optionArray[$i]{'~datasetIllustrative'}
                  : (),
                  $dataset,
                  map { $optionArray[$i]{$_} }
                  qw(dataOverride ~datasetOverride);
                if ( @dataLayers > 1 ) {
                    my $comboDataset;
                    $comboDataset->{usePlaceholderData} =
                      $optionArray[$i]{illustrative}
                      if $optionArray[$i]{illustrative};
                    foreach my $dataLayer (@dataLayers) {
                        foreach my $override (
                            ref $dataLayer eq 'ARRAY'
                            ? @$dataLayer
                            : $dataLayer
                          )
                        {
                            foreach my $itable ( keys %$override ) {
                                if ( 'ARRAY' eq ref $override->{$itable} ) {
                                    for (
                                        my $icolumn = 1 ;
                                        $icolumn < @{ $override->{$itable} } ;
                                        ++$icolumn
                                      )
                                    {
                                        foreach my $irow (
                                            keys
                                            %{ $override->{$itable}[$icolumn] }
                                          )
                                        {
                                            $comboDataset->{$itable}
                                              [$icolumn]{$irow} =
                                              $override->{$itable}[$icolumn]
                                              {$irow};
                                        }
                                    }
                                }
                                else {
                                    $comboDataset->{itable} =
                                      $override->{$itable};
                                }
                            }
                        }
                    }
                    $dataset = $comboDataset;
                }
            }
            $optionArray[$i]{dataset} = $dataset;
        }
    }

    my @loggers;
    my @modelArray;
    if ($#optionArray) {
        my @toNumber = grep { !defined $_->{modelNumberSuffix}; } @optionArray;
        if ( @toNumber > 9 ) {
            $toNumber[ $_ - 1 ]{modelNumberSuffix} = $_ > 9 ? ".$_" : ".0$_"
              foreach 1 .. @toNumber;
        }
        elsif ( @toNumber > 1 ) {
            $toNumber[ $_ - 1 ]{modelNumberSuffix} = ".$_"
              foreach 1 .. @toNumber;
        }
    }
    foreach my $optionNumber ( 0 .. $#optionArray ) {
        my $options = $optionArray[$optionNumber];
        $options->{exporterObject} = undef if $exporter;
        $options->{sharingObjectRef} = \$multiModelSharing if $#optionArray;
        my $model = eval { $options->{PerlModule}->new(%$options) };
        die "\n" . $@ . ( $@ =~ /suitable disclaimer/ ? <<'EOW': '' ) if $@;

To add an additional disclaimer notice, use one of the following methods.

Method 1:
    Use the spreadsheet generator at http://dcmf.co.uk/models/
    and look under "Show additional options".

Method 2:
    Use the pmod.pl command line tool, either through STDIN
    with the option -extraNotice, or with the option
    -extraNotice='Put your additional notice text here'.

Method 3:
    Put something like this in your rules file:
extraNotice:
  - The first line of your notice goes here.
  - The second line of your notice goes here.
  - And so on.

Please do not exceed 140 characters per line.

EOW
        die "$options->{PerlModule}->new(...) has failed" unless $model;

        map { $_->($model); } @{ $options->{requestsToSeeModel} }
          if $options->{requestsToSeeModel};
        $modelArray[$optionNumber]            = $model;
        $forwardLinkFindingRun[$optionNumber] = $model
          if $options->{forwardLinks};
        $options->{revisionText}      ||= '';
        $options->{modelNumberSuffix} ||= '';
        $model->{localTime} = \@localTime;
        $SpreadsheetModel::ShowDimensions = $options->{showDimensions}
          if $options->{showDimensions};
        my $canPriority = $model->can('sheetPriority');
        my @pairs       = $model->worksheetsAndClosures($wbook);

        while ( ( local $_, my $closure ) = splice @pairs, 0, 2 ) {
            my $priority = $canPriority ? $model->sheetPriority($_)
              || 0 : /^(?:Index|Overview)$/is ? 1 : 0;
            my $fullName = $_ . $options->{modelNumberSuffix};
            $sheetDisplayName{$fullName} =
                m#(.*)/#  ? $1 . $options->{modelNumberSuffix}
              : /(.*)\$$/ ? $1
              :             $_ . $options->{modelNumberSuffix};
            push @{ $options->{wsheetRunOrder} }, $fullName;
            push @{ $wsheetShowOrder[$priority] }, $fullName;
            $allClosures{$fullName} = $closure;
            undef $wsheetActive{$_}
              if $options->{activeSheets} && /$options->{activeSheets}/;
            $wsheetPassword{$fullName} = $options->{password}
              if $options->{protect};
        }
        $loggers[$optionNumber] = new SpreadsheetModel::Logger(
            name            => '',
            showFinalTables => $model->{forwardLinks},
            showDetails     => $model->{debug},
        );
        map { push @{ $wsheetShowOrder[ $_->sheetPriority ] }, $_; }
          @{ $model->{standaloneCharts} }
          if $model->{standaloneCharts};
    }

    my %wsheet;
    for ( my $i = $#wsheetShowOrder ; $i >= 0 ; --$i ) {
        my %byDisplayName;
        foreach ( @{ $wsheetShowOrder[$i] } ) {
            if ( UNIVERSAL::isa( $_, 'SpreadsheetModel::Chart' ) ) {
                $_->wsCreate($wbook);
            }
            else {
                my $dn = $sheetDisplayName{$_};
                $wsheet{$_} = $byDisplayName{$dn} ||=
                  $wbook->add_worksheet($dn);
            }
        }
    }

    $wbook->{$_} = $wsheet{$_} foreach keys %wsheet;
    foreach ( 0 .. $#optionArray ) {
        my $options = $optionArray[$_];
        my $model   = $modelArray[$_];
        $wbook->{dataSheet} =
          $wsheet{ 'Input' . $options->{modelNumberSuffix} };
        delete $wbook->{highestAutoTableNumber};

        if ( $forwardLinkFindingRun[$_] ) {
            open my $h2, '>', '/dev/null';
            my $wb2 = $module->new($h2);
            $wb2->setFormats($options);
            $wb2->{findForwardLinks} = 1;
            my @wsheetsAndClosures2 =
              $forwardLinkFindingRun[$_]->worksheetsAndClosures($wb2);
            my %closures2 = @wsheetsAndClosures2;
            my @sheetNames2 = @wsheetsAndClosures2[ grep { !( $_ % 2 ) }
              0 .. $#wsheetsAndClosures2 ];
            $wb2->{$_} = $wb2->add_worksheet($_) foreach @sheetNames2;
            $closures2{$_}->( $wb2->{$_} )
              foreach grep { !/Overview|Index/i } @sheetNames2;
            $wb2->close;
            push @hazardousWaste, $wb2;
        }

        $wbook->{$_} = $options->{$_} foreach grep { exists $options->{$_} } qw(
          copy
          debug
          forwardLinks
          linesAsComment
          mergedRanges
          noLinks
          rowHeight
          tolerateMisordering
          validation
        );
        $wbook->{logger} = $loggers[$_];

        foreach ( @{ $options->{wsheetRunOrder} } ) {
            my $ws = $wsheet{$_};
            delete $ws->{sheetNumber};
            delete $ws->{lastTableNumber};
            $allClosures{$_}->($ws);
            $ws->activate if exists $wsheetActive{$_};
            $ws->fit_to_pages( 1, 0 ) unless /^(?:Index|Overview)/;
            $ws->hide_gridlines(2);
            $ws->protect( $wsheetPassword{$_}, $ws->{protectionOptions} )
              if exists $wsheetPassword{$_};
            $ws->set_footer("&F");
            $ws->set_header("&L&A&C&R&P of &N");
            $ws->set_paper(9);
            $ws->insert_image( 0, 0, $options->{watermarkFile} )
              if $options->{watermarkFile};
        }

        $model->finishWorkbook($wbook)
          if UNIVERSAL::can( $model, 'finishWorkbook' );

        if ($exporter) {
            $exporter->setModel( $options->{modelNumberSuffix},
                $options, $wbook->{logger} );
            $exporter->$_() foreach @exports;
        }

    }

    $multiModelSharing->finish($wbook)
      if UNIVERSAL::can( $multiModelSharing, 'finish' );

    $wbook->close;
    close $fileOrHandle if ref $fileOrHandle;
    $afterClose->() if $afterClose;

    wantarray
      ? (
        0,
        grep {
            # XLSX workbooks are chdir-hazardous waste.
            # XLS workbooks must be disposed of quickly
            # because they hog file descriptors.
            !$_->isa('Spreadsheet::WriteExcel');
          } @hazardousWaste,
        $wbook,
      )
      : 0;

}

1;
