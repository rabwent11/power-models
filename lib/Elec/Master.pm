﻿package Elec;

=head Copyright licence and disclaimer

Copyright 2012-2016 Franck Latrémolière, Reckon LLP and others.

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

sub serviceMap {
    my ($model) = @_;
    my @modules = (
        sheets    => 'Elec::Sheets',
        setup     => 'Elec::Setup',
        charging  => 'Elec::Charging',
        customers => $model->{ulist}
        ? 'Elec::CustomersTyped'
        : 'Elec::Customers',
        tariffs => 'Elec::Tariffs',
        usage   => 'Elec::Usage'
    );
    push @modules, timebands => 'Elec::Timebands'    if $model->{timebands};
    push @modules, timebands => 'Elec::TimebandSets' if $model->{timebandSets};
    push @modules, checksum => 'SpreadsheetModel::Checksum'
      if $model->{checksums};
    push @modules, supply => 'Elec::Supply' if $model->{usetEnergy};
    push @modules, summaries => 'Elec::Summaries'
      if $model->{usetUoS} || $model->{compareppu} || $model->{showppu};
    @modules;
}

sub requiredModulesForRuleset {
    my ( $class, $model ) = @_;
    my %serviceMap = serviceMap($model);
    values %serviceMap;
}

sub register {
    my ( $model, $object ) = @_;
    push @{ $model->{finishList} }, $object;
    $object;
}

sub new {

    my $class      = shift;
    my $model      = bless { inputTables => [], finishList => [], @_ }, $class;
    my %serviceMap = $model->serviceMap;
    my $setup      = $serviceMap{setup}->new($model);
    $setup->registerTimebands( $serviceMap{timebands}->new( $model, $setup ) )
      if $serviceMap{timebands};
    my $customers = $serviceMap{customers}->new( $model, $setup );
    my $usage = $serviceMap{usage}->new( $model, $setup, $customers );
    my $charging = $serviceMap{charging}->new( $model, $setup, $usage );

    foreach
      ( # NB: the order of this list affects the column order in the input data table
        qw(
        usetMatchAssets
        usetBoundaryCosts
        usetRunningCosts
        )
      )
    {
        next unless my $usetName = $model->{$_};
        $charging->$_( $usage->totalUsage( $customers->totalDemand($usetName) ),
            $usetName !~ s/ \(information only\)$//i );
    }

    my $tariffs =
      $serviceMap{tariffs}->new( $model, $setup, $usage, $charging );

    $tariffs->showAverageUnitRateTable($customers)
      if $model->{timebands} && $model->{showAverageUnitRateTable};
    if ( my $usetName = $model->{usetRevenues} ) {
        if ( $model->{showppu} ) {
            $serviceMap{summaries}->new( $model, $setup )
              ->setupByGroup( $customers, $usetName )
              ->summariseTariffs($tariffs);
        }
        else {
            $tariffs->revenues( $customers->totalDemand($usetName) );
        }
    }

    if ( my $usetName = $model->{usetEnergy} ) {
        my $supplyTariffs =
          $serviceMap{supply}->new( $model, $setup, $tariffs,
            $charging->energyCharge->{arguments}{A1} );
        $supplyTariffs->revenues( $customers->totalDemand($usetName) );
        $supplyTariffs->margin( $customers->totalDemand($usetName) )
          if $model->{energyMargin};
        $serviceMap{summaries}->new( $model, $setup )
          ->setupWithTotal( $customers, $usetName )->summariseTariffs(
            $supplyTariffs,
            [ revenueCalculation => $tariffs ],
            [ marginCalculation  => $supplyTariffs ],
          )->addDetailedAssets( $charging, $usage )
          if $model->{compareppu} || $model->{showppu};
    }
    elsif ( $usetName = $model->{usetUoS} ) {
        $serviceMap{summaries}->new( $model, $setup )
          ->setupWithAllCustomers($customers)->summariseTariffs($tariffs)
          ->addDetailedAssets( $charging, $usage );
    }

    $_->finish($model) foreach @{ $model->{finishList} };
    $model;

}

1;
