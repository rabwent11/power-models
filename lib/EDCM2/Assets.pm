﻿package EDCM2;

# Copyright 2009-2012 Energy Networks Association Limited and others.
# Copyright 2013-2017 Franck Latrémolière, Reckon LLP and others.
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

use SpreadsheetModel::Shortcuts ':all';

sub cdcmAssets {

    my ($model) = @_;

    my $assetLevelset = Labelset(
        name => 'All asset levels',
        list => [ split /\n/, <<EOT ] );
GSP
132kV circuits
132kV/EHV
EHV circuits
EHV/HV
132kV/HV
HV circuits
HV/LV
LV circuits
LV customer
HV customer
EOT

    my $allAssets;
    if ( $model->{tableGrouping} ) {
        $allAssets = Stack(
            name          => 'Assets in CDCM model (£)',
            defaultFormat => '0copy',
            cols          => $assetLevelset,
            rows          => 0,
            rowName       => 'Assets in CDCM model (£)',
            sources       => [
                $model->{cdcmComboTable} = Dataset(
                    name       => 'Data from CDCM model',
                    rowFormats => [ '%hard', '0hard', '0hard', '0.000hard', ],
                    cols       => $assetLevelset,
                    rows       => Labelset(
                        list => [
                            'Diversity allowance between'
                              . ' level exit and GSP Group',
                            'System simultaneous maximum load (kW)',
                            'Assets in CDCM model (£)',
                            'Loss adjustment factor to transmission',
                        ]
                    ),
                    data => [
                        [ 0.1, 5e3, undef, 0.1 ],
                        ( map { [ 0.1,   5e3,   5e8, 0.1 ] } 1 .. 5 ),
                        ( map { [ undef, undef, 5e8, undef ] } 1 .. 5 ),
                    ],
                    number     => 1140,
                    dataset    => $model->{dataset},
                    appendTo   => $model->{inputTables},
                    validation => {
                        validate => 'decimal',
                        criteria => '>=',
                        value    => 0,
                    }
                )
            ],
        );
    }
    else {
        $allAssets = Dataset(
            name => 'Assets in CDCM model (£)'
              . ( $model->{transparency} ? '' : ' (from CDCM table 2706)' ),
            defaultFormat => '0hard',
            cols          => $assetLevelset,
            data     => [ undef, map { 5e8 } 2 .. @{ $assetLevelset->{list} } ],
            number   => 1131,
            dataset  => $model->{dataset},
            appendTo => $model->{inputTables},
            validation => {
                validate => 'decimal',
                criteria => '>=',
                value    => 0,
            }
        );
    }

    my $ehvAssets = SumProduct(
        name          => 'EHV assets in CDCM model (£)',
        groupName     => 'Assets in CDCM model',
        defaultFormat => '0softnz',
        matrix        => Constant(
            name  => 'EHV asset levels',
            cols  => $assetLevelset,
            byrow => 1,
            data  => [ [qw(1 1 1 1 1 1 0 0 0 0 0)] ]
        ),
        vector => $allAssets
    );
    $model->{transparency}{dnoTotalItem}{1233} = $ehvAssets
      if $model->{transparency};

    my $hvLvNetAssets = SumProduct(
        name          => 'HV and LV network assets in CDCM model (£)',
        defaultFormat => '0softnz',
        matrix        => Constant(
            name  => 'HV and LV network asset levels',
            cols  => $assetLevelset,
            byrow => 1,
            data  => [ [qw(0 0 0 0 0 0 1 1 1 0 0)] ]
        ),
        vector => $allAssets
    );
    $model->{transparency}{dnoTotalItem}{1235} = $hvLvNetAssets
      if $model->{transparency};

    my $hvLvServAssets = SumProduct(
        name          => 'HV and LV service assets in CDCM model (£)',
        defaultFormat => '0softnz',
        matrix        => Constant(
            name  => 'HV and LV service asset levels',
            cols  => $assetLevelset,
            byrow => 1,
            data  => [ [qw(0 0 0 0 0 0 0 0 0 1 1)] ]
        ),
        vector => $allAssets
    );
    $model->{transparency}{dnoTotalItem}{1231} = $hvLvServAssets
      if $model->{transparency};

    $allAssets, $ehvAssets, $hvLvNetAssets, $hvLvServAssets;

}

sub notionalAssets {

    my (
        $model,          $activeCoincidence,      $reactiveCoincidence,
        $agreedCapacity, $powerFactorInModel,     $tariffCategory,
        $tariffSUimport, $tariffSUexport,         $totalCdcmAssets,
        $useProportions, $gspAndEhvAssetLevelset, $totalCdcmUse,
    ) = @_;

    my $lossFactors = $model->{cdcmComboTable} ? Stack(
        name => 'Loss adjustment factor to transmission'
          . ' for each network level',
        cols    => $gspAndEhvAssetLevelset,
        rows    => 0,
        rowName => 'Loss adjustment factor to transmission',
        sources => [ $model->{cdcmComboTable} ],
      ) : Dataset(
        name => 'Loss adjustment factor to transmission'
          . ' for each network level'
          . ( $model->{transparency} ? '' : ' (from CDCM table 2004)' ),
        cols       => $gspAndEhvAssetLevelset,
        data       => [qw(1 1.01 1.02 1.03 1.04 1.04)],
        number     => 1135,
        dataset    => $model->{dataset},
        appendTo   => $model->{inputTables},
        validation => {
            validate => 'decimal',
            criteria => '>=',
            value    => 0,
        }
      );

    my $diversity = $model->{cdcmComboTable} ? Stack(
        name          => 'Diversity allowance between level exit and GSP Group',
        defaultFormat => '%copy',
        cols          => $gspAndEhvAssetLevelset,
        rows          => 0,
        rowName       => 'Diversity allowance between level exit and GSP Group',
        sources       => [ $model->{cdcmComboTable} ],
      ) : Dataset(
        name => 'Diversity allowance between level exit '
          . 'and GSP Group'
          . ( $model->{transparency} ? '' : ' (from CDCM table 2611)' ),
        defaultFormat => '%hard',
        cols          => $gspAndEhvAssetLevelset,
        data          => [qw(0.1 0.1 0.3 0.3 0.3 0.7)],
        number        => 1105,
        dataset       => $model->{dataset},
        appendTo      => $model->{inputTables}
      );

    my $useTextMatching =
      $model->{legacy201} || $model->{textCustomerCategories};

    my $customerCategory =
      $useTextMatching
      ? Arithmetic(
        name       => 'Tariff type and category',
        arithmetic => '="D"&TEXT(A1,"0000")',
        arguments  => { A1 => $tariffCategory }
      )
      : Arithmetic(
        name          => 'Index of customer category',
        defaultFormat => '0soft',
        arithmetic =>
'=1+(38*MOD(A10,10)+(19*MOD(A100,100)+(19*MOD(A1000,1000)+A1)/20)/10)/5',
        arguments => {
            A1    => $tariffCategory,
            A10   => $tariffCategory,
            A100  => $tariffCategory,
            A1000 => $tariffCategory,
        }
      );

    my $tariffCategoryset = Labelset(
        name => 'Customer categories',
        list => [ split /\n/, <<EOL] );
Category 0000
Category 1000
Category 0100
Category 1100
Category 0010
Not used
Category 0110
Category 1110
Category 0001
Category 1001
Category 0101
Category 1101
Category 0011
Not used
Category 0111
Category 1111
Category 0002
EOL

    my $lossFactorMap = Constant(
        name          => 'Mapping of customer category to loss factor',
        defaultFormat => '0con',
        rows          => $tariffCategoryset,
        data          => [
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(1 2 3 3 4 . 4 4 6 6 5 5 5 . 5 5 5)
            ]
        ],
    );

    my $tariffLossFactor = Arithmetic(
        name       => 'Loss factor to transmission',
        arithmetic => '=INDEX(A8_A9,'
          . (
            $useTextMatching
            ? 'IF(ISNUMBER(SEARCH("?0000",A1)),1,'
              . 'IF(ISNUMBER(SEARCH("?1000",A20)),2,'
              . 'IF(ISNUMBER(SEARCH("??100",A21)),3,'
              . 'IF(ISNUMBER(SEARCH("???10",A22)),4,'
              . 'IF(ISNUMBER(SEARCH("??001",A23)),6,5)))))'
            : $model->{voltageRulesTransparency} ? 'INDEX(A5_A6,A1)'
            :   'IF(A1,IF(MOD(A12,1000),IF(MOD(A13,100),IF(MOD(A14,10),IF(MOD(A15,1000)=1,6,5),4),3),2),1)'
          )
          . ')',
        arguments => {
            $useTextMatching
            ? (
                A1  => $customerCategory,
                A20 => $customerCategory,
                A21 => $customerCategory,
                A22 => $customerCategory,
                A23 => $customerCategory,
              )
            : $model->{voltageRulesTransparency} ? (
                A1    => $customerCategory,
                A5_A6 => $lossFactorMap,
              )
            : (
                A1  => $tariffCategory,
                A12 => $tariffCategory,
                A13 => $tariffCategory,
                A14 => $tariffCategory,
                A15 => $tariffCategory,
            ),
            A8_A9 => $lossFactors,
        },
    );

    my $purpleUseRate = Arithmetic(
        name => 'Peak-time active power consumption'
          . ' adjusted to transmission (kW/kVA)',
        groupName  => 'Active power consumption',
        arithmetic => '=A1*A9',
        arguments  => {
            A1 => $activeCoincidence,
            A9 => $tariffLossFactor,
        }
    );

    $purpleUseRate = [
        $purpleUseRate,
        Arithmetic(
            name => 'Peak-time capacity use adjusted to transmission (kW/kVA)',
            arithmetic => '=SQRT(A1*A2+A3*A4)*A8*A9',
            arguments  => {
                A1 => $activeCoincidence,
                A2 => $activeCoincidence,
                A3 => $reactiveCoincidence,
                A4 => $reactiveCoincidence,
                A8 => $powerFactorInModel,
                A9 => $tariffLossFactor,
            }
        )
      ]
      if $model->{dcp183};

    my $capUseRate = Arithmetic(
        name => 'Active power equivalent of capacity'
          . ' adjusted to transmission (kW/kVA)',
        arithmetic => '=A1*A9',
        $model->{layout}
          && $model->{layout} =~ /matrix/ ? ( newBlock => 1 ) : (),
        arguments => {
            A9 => $powerFactorInModel,
            A1 => $tariffLossFactor,
        }
    );

    my ( $usePropCap, $usePropCollar ) =
      $model->nufCapCollar( $gspAndEhvAssetLevelset, $useProportions->{cols} );

    my $accretion = $model->notionalAssetRates(
        $useTextMatching,
        $model->{voltageRulesTransparency}
        ? $useProportions->{cols}
        : $gspAndEhvAssetLevelset,
        $totalCdcmUse,
        $totalCdcmAssets,
        $lossFactors,
    );

    my $useProportionsCooked = Arithmetic(
        name       => 'Network use factors (second set)',
        groupName  => 'Second set of network use factors',
        arithmetic => '=MAX(A3+0,MIN(A1+0,A2+0))',
        arguments  => {
            A1 => $useProportions,
            A2 => $usePropCap,
            A3 => $usePropCollar,
        }
    );

    my $notionalAssetCalculatorMethod = 'notionalAssetCalculator'
      . ( $model->{voltageRulesTransparency} ? '' : 'Hardcoded' );
    my (
        $assetsCapacity,       $assetsConsumption,
        $assetsCapacityCooked, $assetsConsumptionCooked
      )
      = $model->$notionalAssetCalculatorMethod(
        $tariffCategoryset,    $useProportions,
        $useProportionsCooked, $customerCategory,
        $accretion,            $diversity,
        $capUseRate,           $purpleUseRate,
        $useTextMatching ? undef : $tariffCategory, $usePropCap,
      );

    $model->{transparency}{dnoTotalItem}{1225} = $accretion
      if $model->{transparency};

    my $totalAssetsFixed =
      $model->{transparencyMasterFlag}
      ? Arithmetic(
        name          => 'Total sole use assets for demand (£)',
        newBlock      => 1,
        defaultFormat => '0softnz',
        arithmetic    => '=IF(A123,0,A1)+SUMPRODUCT(A11_A12,A15_A16)',
        arguments     => {
            A123    => $model->{transparencyMasterFlag},
            A1      => $model->{transparency}{baselineItem}{119301},
            A11_A12 => $tariffSUimport,
            A15_A16 => $model->{transparency},
        },
      )
      : GroupBy(
        source        => $tariffSUimport,
        name          => 'Total sole use assets for demand (£)',
        newBlock      => 1,
        defaultFormat => '0softnz'
      );

    $model->{transparency}{dnoTotalItem}{119301} = $totalAssetsFixed
      if $model->{transparency};

    my ( $totalAssetsCapacity, $totalAssetsConsumption ) =
      $model->{transparencyMasterFlag}
      ? (
        map {
            my $name = $_->[0]->objectShortName;
            $name =~ s/\(£\/kVA\)/(£)/;
            Arithmetic(
                name          => $name,
                groupName     => 'Notional assets in EDCM model',
                defaultFormat => '0softnz',
                arithmetic =>
                  '=IF(A123,0,A1)+SUMPRODUCT(A11_A12,A13_A14,A15_A16)',
                arguments => {
                    A123    => $model->{transparencyMasterFlag},
                    A1      => $model->{transparency}{baselineItem}{ $_->[1] },
                    A11_A12 => $_->[0],
                    A13_A14 => $agreedCapacity,
                    A15_A16 => $model->{transparency},
                },
            );
        } ( [ $assetsCapacity, 119303 ], [ $assetsConsumption, 119304 ], )
      )
      : (
        map {
            my $name = $_->objectShortName;
            $name =~ s/\(£\/kVA\)/(£)/;
            SumProduct(
                name          => $name,
                groupName     => 'Notional assets in EDCM model',
                defaultFormat => '0softnz',
                matrix        => $_,
                vector        => $agreedCapacity
            );
        } ( $assetsCapacity, $assetsConsumption )
      );

    if ( $model->{transparency} ) {
        $model->{transparency}{dnoTotalItem}{119303} = $totalAssetsCapacity;
        $model->{transparency}{dnoTotalItem}{119304} = $totalAssetsConsumption;
    }

    my $totalAssetsGenerationSoleUse =
      $model->{transparencyMasterFlag}
      ? Arithmetic(
        name          => 'Total sole use assets for generation (£)',
        defaultFormat => '0softnz',
        arithmetic    => '=IF(A123,0,A1)+SUMPRODUCT(A11_A12,A15_A16)',
        arguments     => {
            A123    => $model->{transparencyMasterFlag},
            A1      => $model->{transparency}{baselineItem}{119302},
            A11_A12 => $tariffSUexport,
            A15_A16 => $model->{transparency},
        },
      )
      : GroupBy(
        source        => $tariffSUexport,
        name          => $tariffSUexport->objectShortName . ' (aggregate)',
        defaultFormat => $tariffSUexport->{defaultFormat}
      );

    $model->{transparency}{dnoTotalItem}{119302} = $totalAssetsGenerationSoleUse
      if $model->{transparency};

    push @{ $model->{calc1Tables} },
      my $totalAssets = Arithmetic(
        name          => 'All notional assets in EDCM (£)',
        arithmetic    => '=A5+A6+A7+A8',
        defaultFormat => '0softnz',
        arguments     => {
            A5 => $totalAssetsFixed,
            A6 => $totalAssetsCapacity,
            A7 => $totalAssetsConsumption,
            A8 => $totalAssetsGenerationSoleUse,
        }
      );
    $model->{transparency}{dnoTotalItem}{1229} = $totalAssets
      if $model->{transparency};

    $lossFactors, $diversity, $accretion, $purpleUseRate, $capUseRate,
      $tariffSUimport,    $assetsCapacity,
      $assetsConsumption, $totalAssetsFixed,
      $totalAssetsCapacity,
      $totalAssetsConsumption,
      $totalAssetsGenerationSoleUse, $totalAssets,
      $assetsCapacityCooked,
      $assetsConsumptionCooked;

}

sub nufCapCollar {

    my ( $model, $gspAndEhvAssetLevelset, $nufLevelset ) = @_;

    my $gspGapInCapCollar = !$model->{tableGrouping} && !$model->{transparency};
    my $levelset = $gspGapInCapCollar ? $gspAndEhvAssetLevelset : $nufLevelset;

    my $usePropCap = Dataset(
        name => 'Maximum network use factor',
        data => [
            $gspGapInCapCollar ? undef : (),
            map { 2 } 2 .. @{ $gspAndEhvAssetLevelset->{list} }
        ],
        cols    => $levelset,
        number  => 1133,
        dataset => $model->{dataset},
    );

    my $usePropCollar = Dataset(
        name => 'Minimum network use factor',
        data => [
            $gspGapInCapCollar ? undef : (),
            map { 0.25 } 2 .. @{ $gspAndEhvAssetLevelset->{list} }
        ],
        cols    => $levelset,
        number  => 1134,
        dataset => $model->{dataset},
    );

    if ( $model->{tableGrouping} ) {
        my $group = Dataset(
            name => 'Maximum and minimum network use factors',
            rows => Labelset(
                list => [ map { $_->{name} } $usePropCap, $usePropCollar, ]
            ),
            cols     => $levelset,
            number   => 1136,
            byrow    => 1,
            data     => [ map { $_->{data} } $usePropCap, $usePropCollar, ],
            dataset  => $model->{dataset},
            appendTo => $model->{inputTables},
        );
        $_ = Stack(
            name    => $_->{name},
            rows    => Labelset( list => [ $_->{name} ] ),
            cols    => $levelset,
            sources => [$group],
        ) foreach $usePropCap, $usePropCollar;
    }
    else {
        push @{ $model->{inputTables} }, $usePropCap, $usePropCollar;
    }

    $usePropCap, $usePropCollar;

}

sub notionalAssetRates {

    my ( $model, $useTextMatching, $ehvAssetLevelset, $totalCdcmUse,
        $totalCdcmAssets, $lossFactors, )
      = @_;

    push @{ $model->{calc1Tables} },
      my $accretion = Arithmetic(
        name       => 'Notional asset rate (£/kW)',
        newBlock   => 1,
        arithmetic => '=IF(A1,A2/A3/A4,0)',
        arguments  => {
            A1 => $totalCdcmUse,
            A2 => $totalCdcmAssets,
            A3 => $totalCdcmUse,
            A4 => $lossFactors
        },
        location => 'Charging rates',
      );

    my $accretion132hvcombined;
    if ( $model->{default132kVHVto132kVEHV} ) {
        my $accretion132hvHard = Dataset(
            name  => 'Override notional asset rate for 132kV/HV (£/kW)',
            lines => 'If there is no non-zero value in this cell '
              . 'and no 132kV/HV in the CDCM then '
              . 'the 132kV/EHV notional asset rate will be used for 132kV/HV.',
            data => [''],
            cols => Labelset(
                list => [
                    $ehvAssetLevelset->{list}[ $#{ $ehvAssetLevelset->{list} } ]
                ]
            ),
            number   => 1132,
            dataset  => $model->{dataset},
            appendTo => $model->{inputTables},
        );
        my $accretion132ehv = Stack(
            name => 'Notional asset rate for 132kV/EHV (£/kW)',
            cols => Labelset(
                list => [
                    $ehvAssetLevelset->{list}
                      [ $#{ $ehvAssetLevelset->{list} } - 3 ]
                ]
            ),
            sources => [$accretion],
        );
        my $accretion132hv = Stack(
            name => 'Calculated notional asset rate for 132kV/HV (£/kW)',
            cols => Labelset(
                list => [
                    $ehvAssetLevelset->{list}[ $#{ $ehvAssetLevelset->{list} } ]
                ]
            ),
            sources => [$accretion],
        );
        my $accretion = Arithmetic(
            name       => 'Default notional asset rate for 132kV/HV (£/kW)',
            arithmetic => '=IF(ISNUMBER(A2),A3,A4)',
            arguments  => {
                A2 => $accretion132hv,
                A3 => $accretion132hv,
                A4 => $accretion132ehv,
            },
        );
        $accretion132hvcombined = Arithmetic(
            name       => 'Notional asset rate for 132kV/HV (£/kW)',
            arithmetic => '=IF(ISNUMBER(A1),IF(A2,A3,A4),A5)',
            arguments  => {
                A1 => $accretion132hvHard,
                A2 => $accretion132hvHard,
                A3 => $accretion132hvHard,
                A4 => $accretion,
                A5 => $accretion,
            },
            location => 'Charging rates',
        );
    }
    else {
        my $accretion132hvHard = Dataset(
            name => 'Override notional asset rate for 132kV/HV (£/kW)',
            $useTextMatching
            ? ()
            : (
                lines => [
                    'This value only affects tariffs if there are'
                      . ' 132kV/HV non-sole-use assets in the EDCM model. '
                      . 'It will not be used if set to zero or blank.',
                    'If the forecast system simultaneous maximum load (kW)'
                      . ' from CDCM users at the 132kV/HV network level is zero,'
                      . ' then a non-zero non-blank value must be entered here.',
                    'An arbitrary non-zero non-blank value should be entered'
                      . ' here if there are no 132kV/HV assets in the EDCM or in the 500 MW model.',
                ]
            ),
            data => ['#VALUE!'],
            cols => Labelset(
                list => [
                    $ehvAssetLevelset->{list}[ $#{ $ehvAssetLevelset->{list} } ]
                ]
            ),
            number   => 1132,
            dataset  => $model->{dataset},
            appendTo => $model->{inputTables},
        );
        $accretion132hvcombined = Arithmetic(
            name => 'Notional asset rate for 132kV/HV (£/kW)',
            $useTextMatching
            ? (
                arithmetic => '=IF(ISNUMBER(A1),A2,A3)',
                arguments  => {
                    A1 => $accretion132hvHard,
                    A2 => $accretion132hvHard,
                    A3 => $accretion,
                }
              )
            : (
                arithmetic => '=IF(ISNUMBER(A1),IF(A2,A3,A4),A5)',
                arguments  => {
                    A1 => $accretion132hvHard,
                    A2 => $accretion132hvHard,
                    A3 => $accretion132hvHard,
                    A4 => $accretion,
                    A5 => $accretion,
                }
            ),
            location => 'Charging rates',
        );
    }

    Stack(
        name      => 'Notional asset rate adjusted (£/kW)',
        groupName => 'Notional asset rate',
        cols      => $ehvAssetLevelset,
        sources   => [ $accretion132hvcombined, $accretion ],
        location  => 'Charging rates',
    );

}

sub notionalAssetCalculator {

    my (
        $model,            $tariffCategoryset,
        $useProportions,   $useProportionsCooked,
        $customerCategory, $accretion,
        $diversity,        $capUseRate,
        $purpleUseRate,    $optionalRawTariffCategoryNotUsed,
        $usePropCapNotUsed,
    ) = @_;

    my $classificationMap = Constant(
        name => 'Network level classification '
          . '(0: not used; 1: same as customer; 2+: higher)',
        defaultFormat => '0con',
        rows          => $tariffCategoryset,
        cols          => $useProportions->{cols},
        data          => [
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(0 1 0 2 0 . 0 3 0 3 0 3 0 . 0 4 0)
            ],
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(0 0 1 1 0 . 2 2 0 0 2 2 0 . 3 3 0)
            ],
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(0 0 0 0 1 . 1 1 0 0 0 0 2 . 2 2 0)
            ],
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(0 0 0 0 0 . 0 0 0 0 1 1 1 . 1 1 1)
            ],
            [
                map { $_ eq '.' ? undef : $_ }
                  qw(0 0 0 0 0 . 0 0 1 1 0 0 0 . 0 0 0)
            ],
        ],
    );

    my $capacityAssetMap = Constant(
        name => 'Network levels treated as capacity assets',
        rows => $tariffCategoryset,
        cols => $useProportions->{cols},
        data => [
            map {
                [ map { !defined $_ ? undef : $_ == 1 ? 1 : 0 } @$_ ]
            } @{ $classificationMap->{data} }
        ],
    );

    my $consumptionAssetMap = Constant(
        name => 'Network levels treated as consumption assets',
        rows => $tariffCategoryset,
        cols => $useProportions->{cols},
        data => [
            map {
                [ map { !defined $_ ? undef : $_ > 1 ? 1 : 0 } @$_ ]
            } @{ $classificationMap->{data} }
        ],
    );

    my $machine = sub {
        my ( $name1, $name2, $useProportions, $useRate, $diversity, @extras, )
          = @_;

        SumProduct(
            name      => $name1,
            groupName => $name2,
            matrix    => SpreadsheetModel::Custom->new(
                name      => $name2,
                groupName => $name2,
                @extras,
                custom => [
                    $model->{voltageRulesTransparency} =~ /old/
                    ? '=IF(INDEX(A5:A6,A4)'
                      . ( $diversity ? '=1' : '>1' )
                      . ',A1*A8'
                      . ( $diversity ? '/(1+A3)' : '' ) . ',0)'
                    : '=INDEX(A5:A6,A4)*A1*A8' . ( $diversity ? '/(1+A3)' : '' )
                ],
                wsPrepare => sub {
                    my ( $self, $wb, $ws, $format, $formula, $pha, $rowh,
                        $colh ) = @_;
                    sub {
                        my ( $x, $y ) = @_;
                        '', $format, $formula->[0],
                          qr/\bA1\b/ =>
                          Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                            $rowh->{A1} + $y,
                            $colh->{A1} + $x
                          ),
                          qr/\bA4\b/ =>
                          Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                            $rowh->{A4} + $y,
                            $colh->{A4}, 0, 1 ),
                          $diversity
                          ? ( # NB: shifted by one to the right because of the GSP entry
                            qr/\bA3\b/ =>
                              Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                                $rowh->{A3}, $colh->{A3} + 1 + $x, 1
                              )
                          )
                          : (),
                          qr/\bA8\b/ =>
                          Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                            $rowh->{A8} + $y,
                            $colh->{A8}, 0, 1 ),
                          qr/\bA5\b/ =>
                          Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                            $rowh->{A5_A6}, $colh->{A5_A6} + $x, 1 ),
                          qr/\bA6\b/ =>
                          Spreadsheet::WriteExcel::Utility::xl_rowcol_to_cell(
                            $rowh->{A5_A6} + $classificationMap->lastRow,
                            $colh->{A5_A6} + $x, 1 );
                    };
                },
                rows      => $useProportions->{rows},
                cols      => $useProportions->{cols},
                arguments => {
                    A1 => $useProportions,
                    A5 => $model->{voltageRulesTransparency} =~ /old/
                    ? $classificationMap
                    : $diversity ? $capacityAssetMap
                    : $consumptionAssetMap,
                    A5_A6 => $model->{voltageRulesTransparency} =~ /old/
                    ? $classificationMap
                    : $diversity ? $capacityAssetMap
                    : $consumptionAssetMap,
                    A4 => $customerCategory,
                    $diversity ? ( A3 => $diversity ) : (),
                    A8 => ref $useRate eq 'ARRAY'
                    ? $useRate
                      ->[1]  # version adjusted for reactive power under DCP 183
                    : $useRate,
                },
            ),
            vector => $accretion,
        );
    };

    $machine->(
        'Capacity assets (£/kVA)',
        'Adjusted network use by capacity',
        $useProportions, $capUseRate, $diversity, newBlock => 1,
      ),
      $machine->(
        'Consumption assets (£/kVA)',
        'Adjusted network use by consumption',
        $useProportions, $purpleUseRate,    # undef, newBlock => 1,
      ),
      $machine->(
        'Second set of capacity assets (£/kVA)',
        'Second set of adjusted network use by capacity',
        $useProportionsCooked,
        $capUseRate,
        $diversity,
        newBlock => 1,
      ),
      $machine->(
        'Second set of consumption assets (£/kVA)',
        'Second set of adjusted network use by consumption',
        $useProportionsCooked,
        $purpleUseRate,    # undef, newBlock => 1,
      );

}

1;
