package Ancillary::Manufacturing;

=head Copyright licence and disclaimer

Copyright 2011-2013 Reckon LLP and others.

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

=head Documentation

my $maker = factory Ancillary::Manufacturing;
$maker->{processStream}->($stream, $optionalFile, $optionsalSha1);
...

See make.pl for an example of how to use this module.

Keys managed here:
~codeValidation
datafile
datafileValidation
dataset
dataOverride
revisionText

Keys defaulted if not existing (default value): 
protect (1)
validation (lenientnomsg)
inputData (dataSheet)

=cut

use warnings;
use strict;
use utf8;
require Storable;
require YAML;

sub _loadModules {
    my $ruleset = shift;
    return 1 unless @_;
    my %savedINC = %INC;
    foreach (@_) {
        eval "require $_";
        if ($@) {
            %INC = %savedINC;
            my $for =
              defined $ruleset->{template} ? " for $ruleset->{template}" : '';
            warn <<EOW;
Cannot load $_$for:
$@
EOW
            return;
        }
    }
    1;
}

sub factory {
    my ($class) = @_;
    my $self = bless {}, $class;
    my $threads1 = 2;
    my ( $workbookModule, $fileExtension, @rulesets, @datasets, %files );

    my $processRuleset = $self->{processRuleset} = sub {
        local $_ = $_[0];
        _loadModules( $_, "$_->{PerlModule}::Master" ) || return;
        $_->{PerlModule}->can('requiredModulesForRuleset')
          and
          _loadModules( $_, $_->{PerlModule}->requiredModulesForRuleset($_) )
          || return;
        $_->{protect}    = 1              unless exists $_->{protect};
        $_->{validation} = 'lenientnomsg' unless exists $_->{validation};
        $_->{inputData}  = 'dataSheet'    unless exists $_->{inputData};
        push @rulesets, $_;
    };

    $self->{processStream} = sub {
        my ( $fileHandle, $fileName, $fileValidation ) = @_;
        binmode $fileHandle, ':utf8';
        local undef $/;
        local $_ = <$fileHandle>;
        my @objects = ();
        if (/^---/s) {
            @objects = YAML::Load($_);
        }
        else {
            eval {
                require JSON;
                @objects = JSON::from_json($_);
            };
            eval {
                require JSON::PP;
                require Encode;
                @objects = JSON::PP::decode_json( Encode::encode_utf8($_) );
            } if $@;
        }
        foreach ( grep { ref $_ eq 'HASH' } @objects ) {
            if ( exists $_->{template} ) {
                $processRuleset->($_);
            }
            elsif ( defined $fileName
                && $fileName =~ /([^\\\/]*%[^\\\/]*)\.(?:yml|yaml|json)$/is )
            {
                $_->{template} = $1;
                $processRuleset->($_);
            }
            else {
                my $datasetName = $_->{datasetName};
                if (  !defined $datasetName
                    && defined $fileName
                    && $fileName =~
                    m#([0-9]+-[0-9]+)?[/\\]?([^/\\]+)\.(?:yml|yaml|json)$#si )
                {
                    $datasetName = $2;
                    $datasetName .= "-$1" if $1;
                }
                push @datasets,
                  {
                    defined $datasetName
                    ? (
                        '~datasetName' => $datasetName,
                        keys %$_
                        ? (
                            defined $fileName
                            ? (
                                '~datasetSource' => {
                                    file       => $fileName,
                                    validation => $fileValidation
                                      || sha1File($fileName)
                                }
                              )
                            : ()
                          )
                        : ( '~datasetSource' => 'Empty dataset' ),
                      )
                    : (),
                    dataset => $_,
                  };
            }
        }
    };

    $self->{useXLSX} = sub {
        if ( eval 'require SpreadsheetModel::WorkbookXLSX' ) {
            $workbookModule ||= 'SpreadsheetModel::WorkbookXLSX';
            $fileExtension = '.xlsx';
        }
        else {
            warn 'Could not load SpreadsheetModel::WorkbookXLSX';
            warn $@;
        }
        $self;
    };

    $self->{override} = sub { $_ = { %$_, @_ } foreach @rulesets; };

    $self->{validate} = sub {
        my ( $perl5dir, $dbString ) = @_;

        unless ( $workbookModule && $fileExtension ) {
            $workbookModule = 'SpreadsheetModel::Workbook';
            $fileExtension  = '.xls';
            require SpreadsheetModel::Workbook;
        }

        # We should have called loadModules by now but we haven't

        use Ancillary::Validation qw(sha1File sourceCodeSha1);
        my $sourceCodeSha1 = sourceCodeSha1($perl5dir);

        # Omitted from validation: this file, and anything "require"d below.
        delete $sourceCodeSha1->{'Ancillary/Manufacturing.pm'};

        my ($db);
        if ( $dbString && require Ancillary::RevisionNumbering ) {
            $db = Ancillary::RevisionNumbering->connect($dbString)
              or warn "Cannot connect to $dbString";
        }
        foreach (@rulesets) {
            $_->{'~codeValidation'} = $sourceCodeSha1;
            delete $_->{'.'};
            $_->{revisionText} = $db->revisionText( YAML::Dump($_) ) if $db;
        }
    };

    $self->{list} = sub {
        foreach my $rule (@rulesets) {
            my @wantTables;
            @wantTables = split /\s+/, $rule->{wantTables}
              if $rule->{wantTables};
            foreach my $data (@datasets) {
                next
                  if keys %{ $data->{dataset} }
                  and grep { !$data->{dataset}{$_} } @wantTables;
                my $spreadsheetFile = $rule->{template};
                $spreadsheetFile .= '-' . $rule->{revisionText}
                  if $rule->{revisionText};
                $spreadsheetFile =~ s/%/$data->{'~datasetName'}/;
                my $number = '';
                $number--
                  while $files{ $spreadsheetFile . $number . $fileExtension };
                $spreadsheetFile .= $number . $fileExtension;
                $files{$spreadsheetFile} = [ $rule, $data ];
            }
        }
        keys %files;
    };

    $self->{listMatching} = sub {
        for ( my $i = 0 ; $i < @rulesets && $i < @datasets ; ++$i ) {
            my $rule = $rulesets[$i];
            my $data = $datasets[$i];

            my $spreadsheetFile = $rule->{template};
            $spreadsheetFile .= '-' . $rule->{revisionText}
              if $rule->{revisionText};
            $spreadsheetFile =~ s/%/$data->{'~datasetName'}/;
            my $number = '';
            $number--
              while $files{ $spreadsheetFile . $number . $fileExtension };
            $spreadsheetFile .= $number . $fileExtension;
            $files{$spreadsheetFile} = [ $rule, $data ];
        }
        keys %files;
    };

    $self->{listMonsterByRuleset} = sub {
        return unless @datasets;
        foreach my $rule (@rulesets) {
            my $spreadsheetFile = $rule->{template};
            $spreadsheetFile .= '-' . $rule->{revisionText}
              if $rule->{revisionText};
            $spreadsheetFile =~ s/%/@datasets
  . '-datasets-'
  . ( $datasets[0]{'~datasetName'} =~ m$([0-9]{4}-[0-9]{2})$ )[0]
/e;
            my $number = '';
            $number--
              while $files{ $spreadsheetFile . $number . $fileExtension };
            $spreadsheetFile .= $number . $fileExtension;
            $files{$spreadsheetFile} = [ $rule, \@datasets ];
        }
        keys %files;
    };

    $self->{listMonsterByDataset} = sub {
        return unless @rulesets;
        foreach my $data (@datasets) {
            my $spreadsheetFile = $data->{'~datasetName'};
            my $number          = '';
            $number--
              while $files{ $spreadsheetFile . $number . $fileExtension };
            $spreadsheetFile .= $number . $fileExtension;
            $files{$spreadsheetFile} = [ \@rulesets, $data ];
        }
        keys %files;
    };

    $self->{prepare} = sub {
        map {
            $files{$_}
              && ( $files{$_} = _mergeRuleData( @{ $files{$_} } ) ) ? $_ : ();
        } @_;
    };

    my $run = $self->{run} = sub {
        map { $workbookModule->create( $_, $files{$_} ); $_; } @_;
    };

    $self->{setThreads} = sub {
        my ($threads) = @_;
        $threads1 = $threads - 1 if $threads > 0 && $threads < 1_000_000;
    };

    $self->{runParallel} = sub {
        require Ancillary::ParallelRunning or goto &$run;
        foreach (@_) {
            Ancillary::ParallelRunning::waitanypid($threads1);
            Ancillary::ParallelRunning::registerpid(
                $workbookModule->bgCreate( $_, $files{$_} ) );
        }
        Ancillary::ParallelRunning::waitanypid(0);
    };

    $self;

}

sub _mergeRuleData {
    my ( $rule, $data ) = @_;
    if ( ref $rule eq 'ARRAY' ) {
        my @result = map { _mergeRuleData( $_, $data ); } @$rule;
        return wantarray ? @result : \@result;
    }
    if ( ref $data eq 'ARRAY' ) {
        my @result = map { _mergeRuleData( $rule, $_ ); } @$data;
        return wantarray ? @result : \@result;
    }
    my $dataset;
    if ( $rule->{dataOverride} ) {
        $dataset = Storable::dclone( $data->{dataset} );
        foreach my $itable ( keys %{ $rule->{dataOverride} } ) {
            for (
                my $icolumn = 1 ;
                $icolumn < @{ $rule->{dataOverride}{$itable} } ;
                ++$icolumn
              )
            {
                foreach my $irow (
                    keys %{ $rule->{dataOverride}{$itable}[$icolumn] } )
                {
                    $dataset->{$itable}[$icolumn]{$irow} =
                      $rule->{dataOverride}{$itable}[$icolumn]{$irow};
                }
            }
        }
    }
    my %options = ( %$rule, %$data, $dataset ? ( dataset => $dataset ) : (), );
    {
        my %opt = %options;
        delete $opt{dataset};
        $options{yaml} = YAML::Dump( \%opt );
    }
    \%options;
}

sub _runInFolder {
    pipe local *IN, local *OUT;
    if ( my $pid = fork ) {
        close OUT;
        my @result = <IN>;
        chomp @result;
        waitpid $pid, 0;
        return "@_ says $?" if $? >> 8;
        return wantarray ? @result : $result[0];
    }
    open STDOUT, '>&OUT';
    close IN;
    chdir shift;
    exec @_;
    die "exec @_: $!";
}

1;