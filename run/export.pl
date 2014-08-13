#!/usr/bin/env perl

=head Copyright licence and disclaimer

Copyright 2012-2013 Franck Latrémolière, Reckon LLP and others.

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
use File::Spec::Functions qw(rel2abs catdir);
use File::Basename 'dirname';
my $homedir;

BEGIN {
    $homedir = dirname( rel2abs( -l $0 ? ( readlink $0, dirname $0) : $0 ) );
    while (1) {
        last if -d catdir( $homedir, 'lib', 'SpreadsheetModel' );
        my $parent = dirname $homedir;
        last if $parent eq $homedir;
        $homedir = $parent;
    }
}
use lib map { catdir( $homedir, $_ ); } qw(cpan lib);

if ( grep { /extract1076from1001/i } @ARGV ) {
    require Compilation::Master;
    Compilation->extract1076from1001;
}

if ( grep { /chedam/i } @ARGV ) {
    require Compilation::ChedamMaster;
    Compilation::Chedam->runFromDatabase;
}

require Compilation::Master;
my $db = Compilation->new;

if ( grep { /\bcsv\b/i } @ARGV ) {
    require Compilation::ExportCsv;
    $db->csvCreate( grep { /small/i } @ARGV );
    exit 0;
}

my $workbookModule =
  ( grep { /^-+xls$/i } @ARGV )
  ? 'SpreadsheetModel::Workbook'
  : 'SpreadsheetModel::WorkbookXLSX';
eval "require $workbookModule" or die $@;

my $options = ( grep { /right/i } @ARGV ) ? { alignment => 'right' } : {};

foreach
  my $modelsMatching ( map { /\ball\b/i ? '.' : m#^/(.+)/$# ? $1 : (); } @ARGV )
{
    require Compilation::ExportTabs;
    my $tablesMatching = join '|', map { /^([0-9]+)$/ ? "^$1" : (); } @ARGV;
    $tablesMatching ||= '.';
    local $_ = "Compilation $modelsMatching$tablesMatching";
    s/ *[^ a-zA-Z0-9-^]//g;
    $db->tableCompilations( $workbookModule, $options,
        $_ => ( $modelsMatching, $tablesMatching ) );
}

if ( grep { /\btscs/i } @ARGV ) {
    require Compilation::ExportTscs;
    my @tablesMatching = map { /^([0-9]+)$/ ? "^$1" : (); } @ARGV;
    @tablesMatching = ('.') unless @tablesMatching;
    $options->{tablesMatching} = \@tablesMatching;
    $db->tscsCreateIntermediateTables unless grep { /norebuild/i } @ARGV;
    $db->tscsCreateOutputFiles( $workbookModule,
        { %$options, ( ( grep { /csv/i } @ARGV ) ? 'csv' : 'wb' ) => 1 } );
}

if ( my ($dcp) = map { /^(dcp\S*)/i ? $1 : /-dcp=(.+)/i ? $1 : (); } @ARGV ) {
    my $options = {};
    if ( my ($yml) = grep { /\.ya?ml$/is } @ARGV ) {
        require YAML;
        $options = YAML::LoadFile($yml);
    }
    $options->{colour} = 'orange' if grep { /^-*orange$/ } @ARGV;
    my ($name) = map { /-+name=(.*)/i ? $1 : (); } @ARGV;
    my ($base) = map { /-+base=(.+)/i ? $1 : (); } @ARGV;
    if ($base) { $name ||= $dcp . ' v ' . $base; }
    else {
        $name ||= $dcp;
        $base = qr/original|clean|after|master|mini|F201|L201|F600|L600/i;
    }
    require Compilation::ExportImpact;
    my @arguments = (
        $workbookModule,
        dcpName   => $name,
        basematch => sub { $_[0] =~ /$base/i; },
        dcpmatch  => sub { $_[0] =~ /[-+]$dcp/i; },
        %$options,
    );
    my @outputs = map { /^-+(cdcm\S*|edcm\S*)/ ? $1 : (); } @ARGV;
    @outputs = qw(cdcm) unless @outputs;
    $db->$_(@arguments) foreach map {
        $_ eq 'cdcm'
          ? qw(cdcmTariffImpact cdcmPpuImpact cdcmRevenueMatrixImpact)
          : $_ eq 'edcm' ? qw(edcmTariffImpact edcmRevenueMatrixImpact)
          :                $_;
    } @outputs;
}
