﻿package EDCM2;

=head Copyright licence and disclaimer

Copyright 2009-2013 Energy Networks Association Limited and others.

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

=head Table numbers used in this file

1111 (shared)
1168 (shared)
1192

=cut

=head Table number availability

110x Inputs Assets Scaling Sheets
111x Inputs Master
112x Assets
113x Assets
114x Scaling
115x 
116x Ldno Master
117x
118x
119x Master

=cut

use warnings;
use strict;
use utf8;
use SpreadsheetModel::Shortcuts ':all';
use EDCM2::Ldno;
use EDCM2::Inputs;
use EDCM2::Assets;
use EDCM2::Locations;
use EDCM2::Charges;
use EDCM2::Generation;
use EDCM2::Scaling;
use EDCM2::Summary;
use EDCM2::Sheets;
use EDCM2::ProcessData;

sub new {

    my $class = shift;
    my $model = {@_};
    $model->{inputTables} = [];
    bless $model, $class;

    $model->processData if $model->{dataset} && keys %{ $model->{dataset} };

    if ( $model->{ldnoRev} && $model->{ldnoRev} =~ /only/i ) {
        $model->{daysInYear} = Dataset(
            name          => 'Days in year',
            defaultFormat => '0hard',
            data          => [365],
            dataset       => $model->{dataset},
            appendTo      => $model->{inputTables},
            number        => 1111,
            validation =>
              { validate => 'decimal', criteria => '>=', value => 0, }
        );
        $model->{ldnoRevTables} = [ $model->ldnoRev ];
        return $model;
    }

    $model->{numLocations} ||= 32;
    $model->{numTariffs}   ||= 32;

    print "$model->{'~datasetName'} $model->{method}: "
      . "$model->{numLocations} locations, $model->{numTariffs} tariff pairs\n";

    my (
        $daysInYear,            $chargeDirect,
        $chargeIndirect,        $chargeRates,
        $chargeExit,            $ehvIntensity,
        $allowedRevenue,        $powerFactorInModel,
        $genPot20p,             $genPotGP,
        $genPotGL,              $genPotCdcmCap20052010,
        $genPotCdcmCapPost2010, $hoursInRed,
    ) = $model->generalInputs;

    my $ehvAssetLevelset = Labelset(
        name => 'EHV asset levels',
        list => [ split /\n/, <<EOT ] );
GSP
132kV circuits
132kV/EHV
EHV circuits
EHV/HV
132kV/HV
EOT

    $model->{ldnoRevTables} = [ $model->ldnoRev() ] if $model->{ldnoRev};

    my (
        $tariffs,                          $importCapacity,
        $exportCapacityExempt,             $exportCapacityChargeablePre2005,
        $exportCapacityChargeable20052010, $exportCapacityChargeablePost2010,
        $tariffSoleUseMeav,                $tariffLoc,
        $tariffCategory,                   $useProportions,
        $activeCoincidence,                $reactiveCoincidence,
        $indirectExposure,                 $nonChargeableCapacity,
        $activeUnits,                      $creditableCapacity,
        $tariffNetworkSupportFactor,       $tariffDaysInYearNot,
        $tariffHoursInRedNot,              $previousChargeImport,
        $previousChargeExport,             $llfcImport,
        $llfcExport,
    ) = $model->tariffInputs($ehvAssetLevelset);

    if ( $model->{PARTIAL} ) {

        my $masterFlag = Dataset(
            name     => 'Are all tariffs additional to the baseline?',
            data     => ['TRUE'],
            dataset  => $model->{dataset},
            appendTo => $model->{inputTables},
            number   => 1190,
        );

        $model->{PARTIAL} = Arithmetic(
            name  => 'Weighting of each tariff for reconciliation of totals',
            lines => [
'0 means that the tariff is active and is included in the table 119x aggregates.',
'-1 means that the tariff is included in the table 119x aggregates but should be removed.',
'1 means that the tariff is active and is not included in the table 119x aggregates.',
            ],
            arithmetic =>
'=IF(OR(IV3,IV4="TRUE",ISNUMBER(SEARCH("[ADDED]",IV2))),1,IF(ISNUMBER(SEARCH("[REMOVED]",IV1)),-1,0))',
            arguments => {
                IV1 => $tariffs,
                IV2 => $tariffs,
                IV3 => $masterFlag,
                IV4 => $masterFlag,
            },
        );

        foreach my $set (
            [
                1191,
                [ 'Baseline total EDCM peak time consumption (kW)', '0hard' ],
                [
'Baseline total marginal effect of indirect cost adder (kVA)',
                    '0hard'
                ],
                [
                    'Baseline total marginal effect of demand adder (£)',
                    '0hard'
                ],
                'Baseline EDCM demand volumes'
            ],
            [
                1192,
                [ 'Baseline total chargeable export capacity (kVA)', '0hard' ],
                [
                    'Baseline total non-exempt 2005-2010 export capacity (kVA)',
                    '0hard'
                ],
                [
                    'Baseline total non-exempt post-2010 export capacity (kVA)',
                    '0hard'
                ],
                'Baseline EDCM generation volumes'
            ],
            [
                1193,
                [ 'Baseline total sole use assets for demand (£)', '0hard' ],
                [
                    'Baseline total sole use assets for generation (£)',
                    '0hard'
                ],
                [ 'Baseline total notional capacity assets (£)',    '0hard' ],
                [ 'Baseline total notional consumption assets (£)', '0hard' ],
                [
'Baseline total non sole use notional assets subject to matching (£)',
                    '0hard'
                ],
                'Baseline EDCM assets and notional assets'
            ],
            [
                1194,
                [
                    'Baseline net forecast EDCM generation revenue (£/year)',
                    '0hard'
                ],
                [ 'Baseline EDCM demand pot (£/year)',              '0hard' ],
                [ 'Baseline revenue from demand charge 1 (£/year)', '0hard' ],
                'Baseline EDCM pots'
            ]
          )
        {
            my @cols;
            foreach my $col ( 1 .. ( $#$set - 1 ) ) {
                push @cols, $model->{PARTIAL}{"ol$set->[0]0$col"} = Dataset(
                    name          => $set->[$col][0],
                    defaultFormat => $set->[$col][1],
                    data          => [ [''] ],
                );
            }
            Columnset(
                name     => $set->[$#$set],
                number   => $set->[0],
                dataset  => $model->{dataset},
                appendTo => $model->{inputTables},
                columns  => \@cols,
            );
        }

    }

    my ( $locations, $locParent, $c1, $a1d, $r1d, $a1g, $r1g ) =
      $model->loadFlowInputs;

    my $importCapacityUnscaled = $importCapacity;
    my $chargeableCapacity     = Arithmetic(
        name          => 'Import capacity not subject to DSM (kVA)',
        defaultFormat => '0soft',
        arguments => { IV1 => $importCapacity, IV2 => $nonChargeableCapacity, },
        arithmetic => '=IV1-IV2',
    );
    my $chargeableCapacity935  = $chargeableCapacity;
    my $activeCoincidence935   = $activeCoincidence;
    my $reactiveCoincidence935 = $reactiveCoincidence;

    my $importEligible = Arithmetic(
        name       => 'Has import charges?',
        arithmetic => '=IV11<>"VOID"',
        arguments  => {
            IV1  => $importCapacity,
            IV11 => $importCapacity,
        }
    );

    $importCapacity = Arithmetic(
        name          => 'Maximum import capacity adjusted for part-year (kVA)',
        defaultFormat => '0soft',
        arithmetic    => '=IF(IV12="VOID",0,(IV1*(1-IV2/IV3)))',
        arguments     => {
            IV1  => $importCapacity,
            IV11 => $importCapacity,
            IV12 => $importCapacity,
            IV2  => $tariffDaysInYearNot,
            IV3  => $daysInYear,
        }
    );

    $chargeableCapacity = Arithmetic(
        name          => 'Non-DSM import capacity adjusted for part-year (kVA)',
        defaultFormat => '0soft',
        arithmetic    => '=IV1-(IV11*(1-IV2/IV3))',
        arguments     => {
            IV1  => $importCapacity,
            IV11 => $nonChargeableCapacity,
            IV2  => $tariffDaysInYearNot,
            IV3  => $daysInYear,
        }
    );

    my $exportCapacityChargeableUnscaled = Arithmetic(
        name          => 'Chargeable export capacity (kVA)',
        defaultFormat => '0soft',
        arithmetic    => '=IV1+IV4+IV5',
        arguments     => {
            IV1 => $exportCapacityChargeablePre2005,
            IV4 => $exportCapacityChargeable20052010,
            IV5 => $exportCapacityChargeablePost2010,
        }
    );

    my $exportEligible = Arithmetic(
        name       => 'Has export charges?',
        arithmetic => '=OR(IV1<>"VOID",IV2<>"VOID",IV3<>"VOID")',
        arguments  => {
            IV1 => $exportCapacityChargeablePre2005,
            IV2 => $exportCapacityChargeable20052010,
            IV3 => $exportCapacityChargeablePost2010,
        }
    );

    my $creditableCapacityUnscaled = $creditableCapacity;

    $_ = Arithmetic(
        name          => $_->objectShortName . ' adjusted for part-year',
        defaultFormat => '0soft',
        arithmetic    => '=IF(IV12="VOID",0,IV1*(1-IV2/IV3))',
        arguments     => {
            IV1  => $_,
            IV11 => $_,
            IV12 => $_,
            IV2  => $tariffDaysInYearNot,
            IV3  => $daysInYear,
        }
      )
      foreach $creditableCapacity, $exportCapacityExempt,
      $exportCapacityChargeablePre2005, $exportCapacityChargeable20052010,
      $exportCapacityChargeablePost2010;

    my $exportCapacityChargeable = Arithmetic(
        name => 'Chargeable export capacity adjusted for part-year (kVA)',
        defaultFormat => '0soft',
        arithmetic    => '=IV1+IV4+IV5',
        arguments     => {
            IV1 => $exportCapacityChargeablePre2005,
            IV4 => $exportCapacityChargeable20052010,
            IV5 => $exportCapacityChargeablePost2010,
        }
    );

    $activeCoincidence = Arithmetic(
        name       => 'Super red kW divided by kVA adjusted for part-year',
        arithmetic => '=IV1*(1-IV2/IV3)/(1-IV4/IV5)',
        arguments  => {
            IV1 => $activeCoincidence,
            IV2 => $tariffHoursInRedNot,
            IV3 => $hoursInRed,
            IV4 => $tariffDaysInYearNot,
            IV5 => $daysInYear,
        }
    );

    $reactiveCoincidence = Arithmetic(
        name       => 'Super red kVAr divided by kVA adjusted for part-year',
        arithmetic => '=IV1*(1-IV2/IV3)/(1-IV4/IV5)',
        arguments  => {
            IV1 => $reactiveCoincidence,
            IV2 => $tariffHoursInRedNot,
            IV3 => $hoursInRed,
            IV4 => $tariffDaysInYearNot,
            IV5 => $daysInYear,
        }
    ) if $reactiveCoincidence;

    my $demandSoleUseAssetUnscaled = Arithmetic(
        name          => 'Sole use asset MEAV for demand (£)',
        defaultFormat => '0soft',
        arithmetic    => '=IF(IV9,IV1*IV2/(IV3+IV4+IV5),0)',
        arguments     => {
            IV1 => $tariffSoleUseMeav,
            IV9 => $tariffSoleUseMeav,
            IV2 => $importCapacity,
            IV3 => $importCapacity,
            IV4 => $exportCapacityExempt,
            IV5 => $exportCapacityChargeable,
        }
    );

    my $generationSoleUseAssetUnscaled = Arithmetic(
        name          => 'Sole use asset MEAV for non-exempt generation (£)',
        defaultFormat => '0soft',
        arithmetic    => '=IF(IV9,IV1*IV21/(IV3+IV4+IV5),0)',
        arguments     => {
            IV1  => $tariffSoleUseMeav,
            IV9  => $tariffSoleUseMeav,
            IV3  => $importCapacity,
            IV4  => $exportCapacityExempt,
            IV5  => $exportCapacityChargeable,
            IV21 => $exportCapacityChargeable,
        }
    );

    my $demandSoleUseAsset = Arithmetic(
        name => 'Demand sole use asset MEAV adjusted for part-year (£)',
        defaultFormat => '0soft',
        arithmetic    => '=IV1*(1-IV2/IV3)',
        arguments     => {
            IV1 => $demandSoleUseAssetUnscaled,
            IV2 => $tariffDaysInYearNot,
            IV3 => $daysInYear,
        }
    );

    my $generationSoleUseAsset = Arithmetic(
        name => 'Generation sole use asset MEAV adjusted for part-year (£)',
        defaultFormat => '0soft',
        arithmetic    => '=IV1*(1-IV2/IV3)',
        arguments     => {
            IV1 => $generationSoleUseAssetUnscaled,
            IV2 => $tariffDaysInYearNot,
            IV3 => $daysInYear,
        }
    );

    my ( $cdcmAssets, $cdcmEhvAssets, $cdcmHvLvShared, $cdcmHvLvService, ) =
      $model->cdcmAssets;

    $reactiveCoincidence = Arithmetic(
        name => 'Super-red kVAr/agreed kVA (capped)',
        arithmetic =>
          '=MAX(MIN(SQRT(1-MIN(1,IV2)^2),IV1),0-SQRT(1-MIN(1,IV3)^2))',
        arguments => {
            IV1 => $reactiveCoincidence,
            IV2 => $activeCoincidence,
            IV3 => $activeCoincidence,
        }
    );

    $reactiveCoincidence935 = Arithmetic(
        name => 'Unadjusted but capped red kVAr/agreed kVA',
        arithmetic =>
          '=MAX(MIN(SQRT(1-MIN(1,IV2)^2),IV1),0-SQRT(1-MIN(1,IV3)^2))',
        arguments => {
            IV1 => $reactiveCoincidence935,
            IV2 => $activeCoincidence935,
            IV3 => $activeCoincidence935,
        }
    );

    my (
        $cdcmUse,                 $lossFactors,
        $diversity,               $redUseRate,
        $capUseRate,              $assetsFixed,
        $assetsCapacity,          $assetsConsumption,
        $totalAssetsFixed,        $totalAssetsCapacity,
        $totalAssetsConsumption,  $totalAssetsGenerationSoleUse,
        $totalEdcmAssets,         $assetsCapacityCooked,
        $assetsConsumptionCooked, $assetsCapacityDoubleCooked,
        $assetsConsumptionDoubleCooked,
      )
      = $model->notionalAssets(
        $activeCoincidence,      $reactiveCoincidence,
        $importCapacity,         $powerFactorInModel,
        $tariffCategory,         $demandSoleUseAsset,
        $generationSoleUseAsset, $cdcmAssets,
        $useProportions,         $ehvAssetLevelset,
      );

    my $edcmRedUse =
      $model->{PARTIAL}
      ? (
        $model->{PARTIAL}{olo}{119101} = Arithmetic(
            name          => 'Total EDCM peak time consumption (kW)',
            defaultFormat => '0softnz',
            arithmetic    => '=IV1+SUMPRODUCT(IV21_IV22*IV51_IV52*IV53_IV54)',
            arguments     => {
                IV1       => $model->{PARTIAL}{ol119101},
                IV21_IV22 => $model->{PARTIAL},
                IV51_IV52 => $redUseRate,
                IV53_IV54 => $importCapacity,
            }
        )
      )
      : SumProduct(
        name          => 'Total EDCM peak time consumption (kW)',
        vector        => $redUseRate,
        matrix        => $importCapacity,
        defaultFormat => '0softnz'
      );

    my $cdcmRedUse = Stack(
        cols => Labelset( list => [ $cdcmUse->{cols}{list}[0] ] ),
        name    => 'Total CDCM peak time consumption (kW)',
        sources => [$cdcmUse]
    );
    $model->{PARTIAL}{oli}{1237} = $cdcmRedUse if $model->{PARTIAL};

    my $overallRedUse = Arithmetic(
        name          => 'Estimate total peak-time consumption (MW)',
        defaultFormat => '0softnz',
        arithmetic    => '=IV1+IV2',
        arguments     => { IV1 => $cdcmRedUse, IV2 => $edcmRedUse }
    );
    $model->{PARTIAL}{oli}{1238} = $overallRedUse if $model->{PARTIAL};

    my $rateExit = Arithmetic(
        name       => 'Transmission exit charging rate (£/kW/year)',
        arithmetic => '=IV1/IV2',
        arguments  => { IV1 => $chargeExit, IV2 => $overallRedUse }
    );
    $model->{PARTIAL}{oli}{1239} = $rateExit if $model->{PARTIAL};

    my $rateDirect = Arithmetic(
        name          => 'Direct cost charging rate',
        arithmetic    => '=IV1/(IV2+IV3+(IV4+IV5)/IV6)',
        defaultFormat => '%soft',
        arguments     => {
            IV1 => $chargeDirect,
            IV2 => $totalEdcmAssets,
            IV3 => $cdcmEhvAssets,
            IV4 => $cdcmHvLvShared,
            IV5 => $cdcmHvLvService,
            IV6 => $ehvIntensity,
        }
    );
    $model->{PARTIAL}{oli}{1245} = $rateDirect if $model->{PARTIAL};

    my $rateRates = Arithmetic(
        name          => 'Network rates charging rate',
        arithmetic    => '=IV1/(IV2+IV3+IV4+IV5)',
        defaultFormat => '%soft',
        arguments     => {
            IV1 => $chargeRates,
            IV2 => $totalEdcmAssets,
            IV3 => $cdcmEhvAssets,
            IV4 => $cdcmHvLvShared,
            IV5 => $cdcmHvLvService,
        }
    );
    $model->{PARTIAL}{oli}{1246} = $rateRates if $model->{PARTIAL};

    my $rateIndirect = Arithmetic(
        name          => 'Indirect cost charging rate',
        arithmetic    => '=IV1/(IV20+IV3+(IV4+IV5)/IV6)',
        defaultFormat => '%soft',
        arguments     => {
            IV1  => $chargeIndirect,
            IV21 => $totalAssetsCapacity,
            IV22 => $totalAssetsConsumption,
            IV3  => $cdcmEhvAssets,
            IV4  => $cdcmHvLvShared,
            IV6  => $ehvIntensity,
            IV20 => $totalEdcmAssets,
            IV5  => $cdcmHvLvService,
        }
    );
    $model->{PARTIAL}{oli}{1250} = $rateIndirect if $model->{PARTIAL};

    my $edcmIndirect = Arithmetic(
        name          => 'Indirect costs on EDCM demand (£/year)',
        defaultFormat => '0softnz',
        arithmetic    => '=IV1*(IV20-IV23)',
        arguments     => {
            IV1  => $rateIndirect,
            IV21 => $totalAssetsCapacity,
            IV22 => $totalAssetsConsumption,
            IV20 => $totalEdcmAssets,
            IV23 => $totalAssetsGenerationSoleUse,
        },
    );
    $model->{PARTIAL}{oli}{1253} = $edcmIndirect if $model->{PARTIAL};

    my $edcmDirect = Arithmetic(
        name => 'Direct costs on EDCM demand except'
          . ' through sole use asset charges (£/year)',
        defaultFormat => '0softnz',
        arithmetic    => '=IV1*(IV20+IV23)',
        arguments     => {
            IV1  => $rateDirect,
            IV20 => $totalAssetsCapacity,
            IV23 => $totalAssetsConsumption,
        },
    );
    $model->{PARTIAL}{oli}{1252} = $edcmDirect if $model->{PARTIAL};

    my $edcmRates = Arithmetic(
        name => 'Network rates on EDCM demand except '
          . 'through sole use asset charges (£/year)',
        defaultFormat => '0softnz',
        arithmetic    => '=IV1*(IV20+IV23)',
        arguments     => {
            IV1  => $rateRates,
            IV20 => $totalAssetsCapacity,
            IV23 => $totalAssetsConsumption,
        },
    );
    $model->{PARTIAL}{oli}{1255} = $edcmRates if $model->{PARTIAL};

    my $fixed3contribution = Arithmetic(
        name          => 'Demand fixed pot contribution p/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV2*IV1*(IV6+IV7+IV88)',
        arguments     => {
            IV1  => $demandSoleUseAsset,
            IV6  => $rateDirect,
            IV7  => $rateIndirect,
            IV88 => $rateRates,
            IV2  => $daysInYear,
        }
    );

    my $fixedDcharge = Arithmetic(
        name          => 'Demand fixed charge p/day (scaled for part year)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV2*IV1*(IV6+IV88)',
        arguments     => {
            IV1  => $demandSoleUseAsset,
            IV6  => $rateDirect,
            IV88 => $rateRates,
            IV2  => $daysInYear,
        }
    );

    my $fixedDchargeTrue = Arithmetic(
        name          => 'Demand fixed charge p/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IF(IV3,(100/IV2*IV1*(IV6+IV88)),0)',
        arguments     => {
            IV1  => $demandSoleUseAssetUnscaled,
            IV6  => $rateDirect,
            IV88 => $rateRates,
            IV2  => $daysInYear,
            IV3  => $importEligible,
        }
    );

    my $fixedGcharge = Arithmetic(
        name          => 'Generation fixed charge p/day (scaled for part year)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV2*IV1*(IV6+IV88)',
        arguments     => {
            IV1  => $generationSoleUseAsset,
            IV6  => $rateDirect,
            IV88 => $rateRates,
            IV2  => $daysInYear,
        }
    );

    my $fixedGchargeUnround = Arithmetic(
        name          => 'Export fixed charge (unrounded) p/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV2*IV1*(IV6+IV88)',
        arguments     => {
            IV1  => $generationSoleUseAssetUnscaled,
            IV6  => $rateDirect,
            IV88 => $rateRates,
            IV2  => $daysInYear,
        }
    );

    my $fixedGchargeTrue = Arithmetic(
        name          => 'Export fixed charge p/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $fixedGchargeUnround, }
    );

    my ( $charges1, $acCoef, $reCoef ) =
      $model->charge1( $tariffLoc, $locations, $locParent, $c1, $a1d, $r1d,
        $a1g, $r1g, $model->preprocess( $locations, $a1d, $r1d, $a1g, $r1g, ),
      ) if $locations;

    my ( $fcpLricDemandCapacityChargeBig,
        $genCredit, $unitRateFcpLricNonDSM, $genCreditCapacity,
        $demandConsumptionFcpLric, )
      = $model->chargesFcpLric(
        $acCoef,                     $activeCoincidence,
        $charges1,                   $daysInYear,
        $reactiveCoincidence,        $reCoef,
        $tariffNetworkSupportFactor, $hoursInRed,
        $hoursInRed,                 $importCapacity,
        $exportCapacityChargeable,   $creditableCapacity,
        $redUseRate,                 $rateExit,
        $activeCoincidence935,       $reactiveCoincidence935,
      );

    $genCredit = Arithmetic(
        name       => 'Generation credit (unrounded) p/kWh',
        arithmetic => '=IF(IV41,(IV2*IV3/(IV4+IV5)),0)',
        arguments  => {
            IV1  => $exportCapacityChargeable,
            IV2  => $genCredit,
            IV21 => $genCredit,
            IV3  => $exportCapacityChargeable,
            IV4  => $exportCapacityChargeable,
            IV5  => $exportCapacityExempt,
            IV41 => $exportCapacityChargeable,
            IV51 => $exportCapacityExempt,
        },
    );

    my $exportCapacityCharge = Arithmetic(
        name          => 'Export capacity charge (unrounded) p/kVA/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IF(IV2,IV4,0)',
        arguments     => {
            IV1 => $exportCapacityChargeable,
            IV2 => $exportEligible,
            IV4 => $model->gCharge(
                $genPot20p,
                $genPotGP,
                $genPotGL,
                $genPotCdcmCap20052010,
                $genPotCdcmCapPost2010,
                $exportCapacityChargeable,
                $exportCapacityChargeable20052010,
                $exportCapacityChargeablePost2010,
                $daysInYear,
            ),
        },
    );

    my $genCreditRound = Arithmetic(
        name          => 'Export super-red unit rate (p/kWh)',
        defaultFormat => '0.000softnz',
        arithmetic    => '=ROUND(IV1,3)',
        arguments     => { IV1 => $genCredit }
    );

    my $genCreditCapacityRound = Arithmetic(
        name          => 'Generation credit (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IF(IV2,ROUND(IV1,2),0)',
        arguments     => {
            IV1 => $genCreditCapacity,
            IV2 => $exportEligible,
        }
    );

    my $exportCapacityChargeRound = Arithmetic(
        name          => 'Export capacity charge (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $exportCapacityCharge }
    );

    my $netexportCapacityChargeUnRound = Arithmetic(
        name =>
          'Net export capacity charge (or credit) (unrounded) (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IF(IV21,(IV1+IV2),0)',
        arguments     => {
            IV1  => $exportCapacityCharge,
            IV2  => $genCreditCapacity,
            IV21 => $exportEligible
        }
    );

    my $netexportCapacityChargeRound = Arithmetic(
        name          => 'Export capacity rate (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $netexportCapacityChargeUnRound, }
    );

    my $generationRevenue =
      $model->{PARTIAL}
      ? (
        $model->{PARTIAL}{olo}{119401} = Arithmetic(
            name          => 'Net forecast EDCM generation revenue (£/year)',
            defaultFormat => '0softnz',
            arithmetic =>
'=IV1+SUMPRODUCT(IV21_IV22*IV51_IV52*IV53_IV54)/100+SUMPRODUCT(IV31_IV32*IV71_IV72*IV73_IV74)*IV75/100+SUMPRODUCT(IV41_IV42*IV83_IV84)*IV85/100',
            arguments => {
                IV1       => $model->{PARTIAL}{ol119401},
                IV21_IV22 => $model->{PARTIAL},
                IV31_IV32 => $model->{PARTIAL},
                IV41_IV42 => $model->{PARTIAL},
                IV51_IV52 => $genCreditRound,
                IV53_IV54 => $activeUnits,
                IV71_IV72 => $netexportCapacityChargeRound,
                IV73_IV74 => $exportCapacityChargeable,
                IV75      => $daysInYear,
                IV83_IV84 => $fixedGcharge,
                IV85      => $daysInYear,
            }
        )
      )
      : Arithmetic(
        name          => 'Net forecast EDCM generation revenue (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
'=SUMPRODUCT(IV51_IV52,IV53_IV54)/100+SUMPRODUCT(IV71_IV72,IV73_IV74)*IV75/100+SUM(IV83_IV84)*IV85/100',
        arguments => {
            IV51_IV52 => $genCreditRound,
            IV53_IV54 => $activeUnits,
            IV71_IV72 => $netexportCapacityChargeRound,
            IV73_IV74 => $exportCapacityChargeable,
            IV75      => $daysInYear,
            IV83_IV84 => $fixedGcharge,
            IV85      => $daysInYear,
        }
      );

    my $chargeOther = Arithmetic(
        name =>
'Revenue less costs and net forecast EDCM generation revenue (£/year)',
        defaultFormat => '0softnz',
        arithmetic    => '=IV1-IV2-IV3-IV4-IV5',
        arguments     => {
            IV1 => $allowedRevenue,
            IV2 => $chargeDirect,
            IV3 => $chargeIndirect,
            IV4 => $chargeRates,
            IV5 => $generationRevenue,
        }
    );
    $model->{PARTIAL}{oli}{1248} = $chargeOther if $model->{PARTIAL};

    my $rateOther = Arithmetic(
        name          => 'Other revenue charging rate',
        arithmetic    => '=IV1/((IV21+IV22)+IV3+IV4)',
        defaultFormat => '%soft',
        arguments     => {
            IV1  => $chargeOther,
            IV21 => $totalAssetsCapacity,
            IV22 => $totalAssetsConsumption,
            IV3  => $cdcmEhvAssets,
            IV4  => $cdcmHvLvShared,
            IV2  => $totalEdcmAssets,
            IV5  => $cdcmHvLvService,
            IV9  => $totalAssetsGenerationSoleUse,
        }
    );
    $model->{PARTIAL}{oli}{1249} = $rateOther if $model->{PARTIAL};

    my $capacity3 = Arithmetic(
        name          => 'Capacity pot contribution p/kVA/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV3*((IV1+IV53)*(IV6+IV7+IV8+IV9)+IV41*IV42)',
        arguments     => {
            IV3  => $daysInYear,
            IV1  => $assetsCapacity,
            IV53 => $assetsConsumption,
            IV41 => $rateExit,
            IV42 => $redUseRate,
            IV6  => $rateDirect,
            IV7  => $rateIndirect,
            IV8  => $rateRates,
            IV9  => $rateOther,
        }
    );

    my $revenue3 = Arithmetic(
        name          => 'Pot contribution £/year',
        defaultFormat => '0softnz',
        arithmetic    => '=IV9*0.01*(IV1+IV2*IV3)',
        arguments     => {
            IV1 => $fixed3contribution,
            IV2 => $capacity3,
            IV3 => $importCapacity,
            IV9 => $daysInYear,
        }
    );

    push @{ $model->{calc3Tables} }, my $totalRevenue3 =
      $model->{PARTIAL}
      ? (
        $model->{PARTIAL}{olo}{119402} = Arithmetic(
            name          => 'Pot (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=IV1+SUMPRODUCT(IV11_IV12*IV15_IV16)',
            arguments     => {
                IV1       => $model->{PARTIAL}{ol119402},
                IV11_IV12 => $revenue3,
                IV15_IV16 => $model->{PARTIAL},
            },
        )
      )
      : GroupBy(
        name          => 'Pot £/year',
        defaultFormat => '0softnz',
        source        => $revenue3
      );

    my ( $scalingChargeFixed, $scalingChargeCapacity );

    my $capacityChargeT = Arithmetic(
        name          => 'Capacity charge p/kVA/day (exit only)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=100/IV2*IV41*IV1',
        arguments     => {
            IV2  => $daysInYear,
            IV41 => $rateExit,
            IV1  => $redUseRate,
        }
    );

    $model->{summaryInformationColumns}[1] = Arithmetic(
        name          => 'Transmission exit charge (£/year)',
        defaultFormat => '0softnz',
        arithmetic    => '=0.01*IV9*IV1*IV2',
        arguments     => {
            IV1 => $importCapacity,
            IV2 => $capacityChargeT,
            IV9 => $daysInYear,
            IV7 => $tariffDaysInYearNot,
        },
    );

    my $importCapacityExceededAdjustment = Arithmetic(
        name =>
          'Adjustment to exceeded import capacity charge for DSM (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic =>
'=IF(IV1=0,0,(1-IV4/IV5)*(IV3+IF(IV23=0,0,(IV2*IV21*(IV22-IV24)/(IV9-IV91)))))',
        defaultFormat => '0.00softnz',
        arguments     => {
            IV3  => $fcpLricDemandCapacityChargeBig,
            IV4  => $chargeableCapacity,
            IV5  => $importCapacity,
            IV1  => $importCapacity,
            IV2  => $unitRateFcpLricNonDSM,
            IV21 => $activeCoincidence935,
            IV23 => $activeCoincidence935,
            IV22 => $hoursInRed,
            IV24 => $tariffHoursInRedNot,
            IV9  => $daysInYear,
            IV91 => $tariffDaysInYearNot,
        },
        defaultFormat => '0.00softnz'
    );

    push @{ $model->{calc2Tables} }, my $unitRateFcpLricDSM = Arithmetic(
        name          => 'Super red unit rate adjusted for DSM (p/kWh)',
        arithmetic    => '=IF(IV6=0,1,IV4/IV5)*IV1',
        defaultFormat => '0.000softnz',
        arguments     => {
            IV1 => $unitRateFcpLricNonDSM,
            IV4 => $chargeableCapacity,
            IV5 => $importCapacity,
            IV6 => $importCapacity,
        }
    );

    my $capacityChargeT1 = Arithmetic(
        name          => 'Import capacity charge from charge 1 (p/VA/day)',
        arithmetic    => '=IF(IV6=0,1,IV4/IV5)*IV1',
        defaultFormat => '0.00softnz',
        arguments     => {
            IV1 => $fcpLricDemandCapacityChargeBig,
            IV4 => $chargeableCapacity,
            IV5 => $importCapacity,
            IV6 => $importCapacity,
        }
    );

    $capacityChargeT = Arithmetic(
        name          => 'Import capacity charge before scaling (p/VA/day)',
        arithmetic    => '=IV7+IV1',
        defaultFormat => '0.00softnz',
        arguments     => {
            IV1 => $capacityChargeT1,
            IV7 => $capacityChargeT,
        }
    );
    $model->{Thursday31} = [
        Arithmetic(
            name          => 'FCP/LRIC capacity-based charge (£/year)',
            arithmetic    => '=IV1*IV4*IV9/100',
            defaultFormat => '0softnz',
            arguments     => {
                IV1 => $model->{demandCapacityFcpLric},
                IV4 => $chargeableCapacity,
                IV9 => $daysInYear,
            }
        ),
        Arithmetic(
            name          => 'FCP/LRIC unit-based charge (£/year)',
            arithmetic    => '=IV1*IV4*IV9/100',
            defaultFormat => '0softnz',
            arguments     => {
                IV1 => $model->{demandConsumptionFcpLric},
                IV4 => $chargeableCapacity,
                IV9 => $daysInYear,
            }
        ),
    ];
    my $tariffHoursInRed = Arithmetic(
        name          => 'Number of super-red hours connected in year',
        defaultFormat => '0softnz',
        arithmetic    => '=IV2-IV1',
        arguments     => {
            IV2 => $hoursInRed,
            IV1 => $tariffHoursInRedNot,

        }
    );

    my $demandScalingShortfall =
      $model->{PARTIAL}
      ? (
        Arithmetic(
            name          => 'Additional amount to be recovered (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=IV1-(IV2+IV3)*IV4-IV5*IV6'
              . ( $model->{NODEMANDCHARGE1} ? '' : '-IV9' ),
            arguments => {
                IV1 => $totalRevenue3,
                IV2 => $rateDirect,
                IV3 => $rateRates,
                IV4 => $model->{PARTIAL}{olo}{119301},
                IV5 => $rateExit,
                IV6 => $model->{PARTIAL}{olo}{119101},
                $model->{NODEMANDCHARGE1}
                ? ()
                : (
                    IV9 => (
                        $model->{PARTIAL}{olo}{119403} = Arithmetic(
                            name => 'Revenue from demand charge 1 (£/year)',
                            defaultFormat => '0softnz',
                            arithmetic =>
'=IV1+(SUMPRODUCT(IV64_IV65,IV31_IV32,IV33_IV34)+SUMPRODUCT(IV66_IV67,IV41_IV42,IV43_IV44,IV35_IV36,IV51_IV52)/IV54)*IV9/100',
                            arguments => {
                                IV1       => $model->{PARTIAL}{ol119403},
                                IV31_IV32 => $capacityChargeT1,
                                IV33_IV34 => $importCapacity,
                                IV9       => $daysInYear,
                                IV41_IV42 => $unitRateFcpLricDSM,
                                IV43_IV44 => $activeCoincidence935,
                                IV35_IV36 => $importCapacityUnscaled,
                                IV51_IV52 => $tariffHoursInRed,
                                IV54      => $daysInYear,
                                IV64_IV65 => $model->{PARTIAL},
                                IV66_IV67 => $model->{PARTIAL},
                            },
                        )
                    ),
                ),
            },
        )
      )
      : Arithmetic(
        name          => 'Additional amount to be recovered (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
'=IV1-(SUM(IV21_IV22)+SUMPRODUCT(IV31_IV32,IV33_IV34)+SUMPRODUCT(IV41_IV42,IV43_IV44,IV35_IV36,IV51_IV52)/IV54)*IV9/100',
        arguments => {
            IV1       => $totalRevenue3,
            IV31_IV32 => $capacityChargeT,
            IV33_IV34 => $importCapacity,
            IV9       => $daysInYear,
            IV21_IV22 => $fixedDcharge,
            IV41_IV42 => $unitRateFcpLricDSM,
            IV43_IV44 => $activeCoincidence935,
            IV35_IV36 => $importCapacityUnscaled,
            IV51_IV52 => $tariffHoursInRed,
            IV54      => $daysInYear,
        }
      );
    $model->{PARTIAL}{oli}{1254} = $demandScalingShortfall if $model->{PARTIAL};

    $model->fudge41(
        $activeCoincidence,             $importCapacity,
        $edcmIndirect,                  $edcmDirect,
        $edcmRates,                     $daysInYear,
        \$capacityChargeT,              \$demandScalingShortfall,
        $indirectExposure,              $assetsCapacityDoubleCooked,
        $assetsConsumptionDoubleCooked, $reactiveCoincidence,
        $powerFactorInModel,
    );

    ($scalingChargeCapacity) = $model->demandScaling41(
        $importCapacity,       $demandScalingShortfall,
        $daysInYear,           $assetsFixed,
        $assetsCapacityCooked, $assetsConsumptionCooked,
        $capacityChargeT,      $fixedDcharge,
    );

    $model->{summaryInformationColumns}[2] = Arithmetic(
        name          => 'Direct cost allocation (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
'=IV1*(MAX(IV2,0-(IV21+IF(IV22=0,0,(1-IV55/IV54)*IV31/(IV32-IV56)*IF(IV52=0,1,IV51/IV53)*IV5))))*IV3*0.01*IV7/IV9',
        arguments => {
            IV1  => $importCapacity,
            IV2  => $scalingChargeCapacity,
            IV21 => $capacityChargeT,
            IV22 => $activeCoincidence935,
            IV5  => $demandConsumptionFcpLric,
            IV51 => $chargeableCapacity,
            IV52 => $importCapacity,
            IV53 => $importCapacity,
            IV3  => $daysInYear,
            IV7  => $edcmDirect,
            IV8  => $edcmRates,
            IV9  => $demandScalingShortfall,
            IV54 => $hoursInRed,
            IV55 => $tariffHoursInRedNot,
            IV56 => $tariffDaysInYearNot,
            IV31 => $daysInYear,
            IV32 => $daysInYear,
        },
    );

    $model->{summaryInformationColumns}[4] = Arithmetic(
        name          => 'Network rates allocation (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
'=IV1*(MAX(IV2,0-(IV21+IF(IV22=0,0,(1-IV55/IV54)*IV31/(IV32-IV56)*IF(IV52=0,1,IV51/IV53)*IV5))))*IV3*0.01*IV8/IV9',
        arguments => {
            IV1  => $importCapacity,
            IV2  => $scalingChargeCapacity,
            IV21 => $capacityChargeT,
            IV22 => $activeCoincidence935,
            IV5  => $demandConsumptionFcpLric,
            IV51 => $chargeableCapacity,
            IV52 => $importCapacity,
            IV53 => $importCapacity,
            IV3  => $daysInYear,
            IV7  => $edcmDirect,
            IV8  => $edcmRates,
            IV9  => $demandScalingShortfall,
            IV54 => $hoursInRed,
            IV55 => $tariffHoursInRedNot,
            IV56 => $tariffDaysInYearNot,
            IV31 => $daysInYear,
            IV32 => $daysInYear,
        },
    );

    $model->{summaryInformationColumns}[7] = Arithmetic(
        name          => 'Demand scaling asset based (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
'=IV1*(MAX(IV2,0-(IV21+IF(IV22=0,0,(1-IV55/IV54)*IV31/(IV32-IV56)*IF(IV52=0,1,IV51/IV53)*IV5))))*IV3*0.01*(1-(IV8+IV7)/IV9)',
        arguments => {
            IV1  => $importCapacity,
            IV2  => $scalingChargeCapacity,
            IV21 => $capacityChargeT,
            IV22 => $activeCoincidence935,
            IV5  => $demandConsumptionFcpLric,
            IV51 => $chargeableCapacity,
            IV52 => $importCapacity,
            IV53 => $importCapacity,
            IV3  => $daysInYear,
            IV7  => $edcmDirect,
            IV8  => $edcmRates,
            IV9  => $demandScalingShortfall,
            IV54 => $hoursInRed,
            IV55 => $tariffHoursInRedNot,
            IV56 => $tariffDaysInYearNot,
            IV31 => $daysInYear,
            IV32 => $daysInYear,
        },
    );

    my $importCapacityScaled =
      $scalingChargeCapacity
      ? Arithmetic(
        name          => 'Total import capacity charge p/kVA/day',
        defaultFormat => '0.00softnz',
        arithmetic    => '=MAX(0-(IV3*IV31*IV33/IV32),IV1+IV2)',
        arguments     => {
            IV1  => $capacityChargeT,
            IV3  => $unitRateFcpLricNonDSM,
            IV31 => $activeCoincidence,
            IV32 => $daysInYear,
            IV33 => $hoursInRed,
            IV2  => $scalingChargeCapacity,
        }
      )
      : Stack( sources => [$capacityChargeT] );

    my $SuperRedRateFcpLric = Arithmetic(
        name => 'Super red rate p/kWh',
        arithmetic =>
'=IF(IV3,IF(IV1=0,IV9,MAX(0,MIN(IV4,IV41+(IV5/IV11*(IV7-IV71)/(IV8-IV81))))),0)',
        arguments => {
            IV1  => $activeCoincidence,
            IV11 => $activeCoincidence935,
            IV3  => $importEligible,
            IV4  => $unitRateFcpLricDSM,
            IV41 => $unitRateFcpLricDSM,
            IV9  => $unitRateFcpLricDSM,
            IV5  => $importCapacityScaled,
            IV51 => $demandConsumptionFcpLric,
            IV7  => $daysInYear,
            IV71 => $tariffDaysInYearNot,
            IV8  => $hoursInRed,
            IV81 => $tariffHoursInRedNot,
        }
    ) if $unitRateFcpLricDSM;

    push @{ $model->{calc4Tables} },
      my $importCapacityScaledSaved = $importCapacityScaled;

    $importCapacityScaled = Arithmetic(
        name       => 'Import capacity charge p/kVA/day',
        arithmetic => '=IF(IV3,MAX(0,IV1),0)',
        arguments  => {
            IV1 => $importCapacityScaled,
            IV3 => $importEligible,
        },
        defaultFormat => '0.00softnz'
    );

    my $importCapacityExceeded = Arithmetic(
        name          => 'Exceeded import capacity charge (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IV7+IV2',
        defaultFormat => '0.00softnz',
        arguments     => {
            IV3 => $fcpLricDemandCapacityChargeBig,
            IV2 => $importCapacityExceededAdjustment,
            IV4 => $chargeableCapacity,
            IV5 => $importCapacity,
            IV1 => $importCapacity,
            IV7 => $importCapacityScaled,
        },
        defaultFormat => '0.00softnz'
    );

    $model->{summaryInformationColumns}[5] = Arithmetic(
        name          => 'FCP/LRIC charge (£/year)',
        defaultFormat => '0softnz',
        arithmetic =>
          '=0.01*(IV11*IV9*IV2+IV1*IV4*IV8*(IV6-IV61)*(IV91/(IV92-IV71)))',
        arguments => {
            IV1  => $importCapacity,
            IV2  => $fcpLricDemandCapacityChargeBig,
            IV3  => $capacityChargeT->{arguments}{IV1},
            IV9  => $daysInYear,
            IV4  => $unitRateFcpLricDSM,
            IV41 => $activeCoincidence,
            IV6  => $hoursInRed,
            IV61 => $tariffHoursInRedNot,
            IV8  => $activeCoincidence935,
            IV91 => $daysInYear,
            IV92 => $daysInYear,
            IV71 => $tariffDaysInYearNot,
            IV11 => $chargeableCapacity,
            IV51 => $importCapacity,
            IV62 => $importCapacity,

        },
    );

    push @{ $model->{tablesG} }, $genCredit, $genCreditCapacity,
      $exportCapacityCharge;

    my $fixedDchargeTrueRound = Arithmetic(
        name          => 'Import fixed charge (p/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $fixedDchargeTrue, },
    );

    my $SuperRedRateFcpLricRound = Arithmetic(
        name          => 'Import super-red unit rate (p/kWh)',
        defaultFormat => '0.000softnz',
        arithmetic    => '=ROUND(IV1,3)',
        arguments     => { IV1 => $SuperRedRateFcpLric, },
    );

    my $importCapacityScaledRound = Arithmetic(
        name          => 'Import capacity rate (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $importCapacityScaled, },
    );

    my $exportCapacityExceeded = Arithmetic(
        name          => 'Export exceeded capacity rate (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=IV1',
        arguments     => { IV1 => $exportCapacityChargeRound, },
    );

    my $importCapacityExceededRound = Arithmetic(
        name          => 'Import exceeded capacity rate (p/kVA/day)',
        defaultFormat => '0.00softnz',
        arithmetic    => '=ROUND(IV1,2)',
        arguments     => { IV1 => $importCapacityExceeded, },
    );

    push @{ $model->{calc4Tables} }, $SuperRedRateFcpLric,
      $importCapacityScaled,
      $fixedDchargeTrue, $importCapacityExceeded, $exportCapacityChargeRound,
      $fixedGchargeTrue;

    push @{ $model->{tariffTables} }, my $thisIsTheTariffTable = Columnset(
        name    => 'EDCM charge',
        columns => [
            Stack( sources => [$tariffs] ),
            $SuperRedRateFcpLricRound,
            $fixedDchargeTrueRound,
            $importCapacityScaledRound,
            $importCapacityExceededRound,
            Stack( sources => [$genCreditRound] ),
            Stack( sources => [$fixedGchargeTrue] ),
            Stack( sources => [$netexportCapacityChargeRound] ),
            $exportCapacityExceeded,
        ]
    );

    return $model unless $model->{summaries};

    my $format0withLine = [ base => '0soft', left => 5, left_color => 8 ];

    my @revenueBitsD = (

        Arithmetic(
            name          => 'Capacity charge for demand (£/year)',
            defaultFormat => $format0withLine,
            arithmetic    => '=0.01*IV9*IV8*IV1',
            arguments     => {
                IV1 => $importCapacityScaledRound,
                IV9 => $daysInYear,
                IV7 => $tariffDaysInYearNot,
                IV8 => $importCapacity,
            }
        ),

        Arithmetic(
            name          => 'Super red charge for demand (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=0.01*(IV9-IV7)*IV1*IV6*(IV91/(IV92-IV71))*IV8',
            arguments     => {
                IV1  => $SuperRedRateFcpLricRound,
                IV9  => $hoursInRed,
                IV7  => $tariffHoursInRedNot,
                IV6  => $importCapacity,
                IV8  => $activeCoincidence935,
                IV91 => $daysInYear,
                IV92 => $daysInYear,
                IV71 => $tariffDaysInYearNot
            }
        ),

        Arithmetic(
            name          => 'Fixed charge for demand (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=0.01*(IV9-IV7)*IV1',
            arguments     => {
                IV1 => $fixedDchargeTrueRound,
                IV9 => $daysInYear,
                IV7 => $tariffDaysInYearNot,
            }
        ),

    );

    my @revenueBitsG = (

        Arithmetic(
            name => 'Net capacity charge (or credit) for generation (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=0.01*IV9*IV8*IV1',
            arguments     => {
                IV1 => $netexportCapacityChargeRound,
                IV9 => $daysInYear,
                IV8 => $exportCapacityChargeable,
            }
        ),

        Arithmetic(
            name          => 'Fixed charge for generation (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=0.01*(IV9-IV7)*IV1',
            arguments     => {
                IV1 => $fixedGchargeTrue,
                IV9 => $daysInYear,
                IV7 => $tariffDaysInYearNot,
            }
        ),

        Arithmetic(
            name          => 'Super red credit (£/year)',
            defaultFormat => '0softnz',
            arithmetic    => '=0.01*IV1*IV6',
            arguments     => {
                IV1 => $genCreditRound,
                IV6 => $activeUnits,
            }
        ),

    );

    my $rev1d = Stack( sources => [$previousChargeImport] );

    my $rev1g = Stack( sources => [$previousChargeExport] );

    my $rev2d = Arithmetic(
        name          => 'Total for demand (£/year)',
        defaultFormat => $format0withLine,
        arithmetic    => '=' . join( '+', map { "IV$_" } 1 .. @revenueBitsD ),
        arguments =>
          { map { ( "IV$_" => $revenueBitsD[ $_ - 1 ] ) } 1 .. @revenueBitsD },
    );

    my $rev2g = Arithmetic(
        name          => 'Total for generation (£/year)',
        defaultFormat => $format0withLine,
        arithmetic    => '=' . join( '+', map { "IV$_" } 1 .. @revenueBitsG ),
        arguments =>
          { map { ( "IV$_" => $revenueBitsG[ $_ - 1 ] ) } 1 .. @revenueBitsG },
    );

    my $change1d = Arithmetic(
        name          => 'Change (demand) (£/year)',
        arithmetic    => '=IV1-IV4',
        defaultFormat => '0softpm',
        arguments     => { IV1 => $rev2d, IV4 => $rev1d }
    );

    my $change1g = Arithmetic(
        name          => 'Change (generation) (£/year)',
        arithmetic    => '=IV1-IV4',
        defaultFormat => '0softpm',
        arguments     => { IV1 => $rev2g, IV4 => $rev1g }
    );

    my $change2d = Arithmetic(
        name          => 'Change (demand) (%)',
        arithmetic    => '=IF(IV1,IV3/IV4-1,"")',
        defaultFormat => '%softpm',
        arguments     => { IV1 => $rev1d, IV3 => $rev2d, IV4 => $rev1d }
    );

    my $change2g = Arithmetic(
        name          => 'Change (generation) (%)',
        arithmetic    => '=IF(IV1,IV3/IV4-1,"")',
        defaultFormat => '%softpm',
        arguments     => { IV1 => $rev1g, IV3 => $rev2g, IV4 => $rev1g }
    );

    my $soleUseAssetChargeUnround = Arithmetic(
        name          => 'Fixed charge for demand (unrounded) (£/year)',
        defaultFormat => $format0withLine,
        arithmetic    => '=0.01*(IV9-IV7)*IV1',
        arguments     => {
            IV1 => $fixedDchargeTrue,
            IV9 => $daysInYear,
            IV7 => $tariffDaysInYearNot,
        }
    );

    $model->{summaryInformationColumns}[0] = $soleUseAssetChargeUnround;

    push @{ $model->{revenueTables} }, Columnset(
        name    => 'Horizontal information',
        columns => [
            (
                map { Stack( sources => [$_] ) }
                  @{ $thisIsTheTariffTable->{columns} }
            ),
            @revenueBitsD,
            @revenueBitsG,
            $rev2d, $rev1d,
            $change1d,
            $change2d,
            1 ? ()
            : (
                Arithmetic(
                    name          => "Super red units (kWh)",
                    defaultFormat => '0softnz',
                    arithmetic    => '=IV1*(IV3-IV7)*IV5',
                    arguments     => {
                        IV3 => $hoursInRed,
                        IV7 => $tariffHoursInRedNot,
                        IV1 => $activeCoincidence935,
                        IV5 => $importCapacityUnscaled,
                    }
                ),
                ( map { Stack( sources => [$_] ) } $chargeableCapacity935 ),
            ),
            $rev2g, $rev1g,
            $change1g,
            $change2g,
            ( grep { $_ } @{ $model->{summaryInformationColumns} } ),
            Arithmetic(
                name          => 'Check (£/year)',
                defaultFormat => '0softnz',
                arithmetic    => join(
                    '', '=IV1',
                    map {
                        $model->{summaryInformationColumns}[$_]
                          ? ( "-IV" . ( 20 + $_ ) )
                          : ()
                    } 0 .. $#{ $model->{summaryInformationColumns} }
                ),
                arguments => {
                    IV1 => $rev2d,
                    map {
                        $model->{summaryInformationColumns}[$_]
                          ? (
                            "IV" . ( 20 + $_ ),
                            $model->{summaryInformationColumns}[$_]
                          )
                          : ()
                    } 0 .. $#{ $model->{summaryInformationColumns} }
                }
            ),
        ]
    );

    my $totalForDemandAllTariffs = GroupBy(
        source        => $rev2d,
        name          => 'Total for demand across all tariffs (£/year)',
        defaultFormat => '0softnz'
    );

    my $totalForGenerationAllTariffs = GroupBy(
        source        => $rev2g,
        name          => 'Total for generation across all tariffs (£/year)',
        defaultFormat => '0softnz'
    );

    push @{ $model->{revenueTables} }, my $totalAllTariffs = Columnset(
        name    => 'Total for all tariffs (£/year)',
        columns => [
            Constant(
                name          => 'This column is not used',
                defaultFormat => '0con',
                data          => [ [''] ]
            ),
            $totalForDemandAllTariffs,
            $totalForGenerationAllTariffs,
            Arithmetic(
                name          => 'Total for all tariffs (£/year)',
                defaultFormat => '0softnz',
                arithmetic    => '=IV1+IV2',
                arguments     => {
                    IV1 => $totalForDemandAllTariffs,
                    IV2 => $totalForGenerationAllTariffs,
                }
            )
        ]
    );

    push @{ $model->{TotalsTables} },
      Columnset(
        name    => 'Total EDCM revenue (£/year)',
        columns => [
            Arithmetic(
                name => 'All EDCM tariffs including discounted LDNO (£/year)',
                defaultFormat => '0softnz',
                arithmetic    => '=IV1+IV2+IV3',
                arguments     => {
                    IV1 => $totalForDemandAllTariffs,
                    IV2 => $totalForGenerationAllTariffs,
                    IV3 => $model->{ldnoRevTables}->[1],
                }
            )
        ]
      ) if $model->{ldnoRevTables};

    my $revenue = $model->revenue(
        $daysInYear,             $tariffs,
        $importCapacity,         $exportCapacityChargeable,
        $activeUnits,            $fixedDcharge,
        $fixedGcharge,           $importCapacityScaledSaved,
        $exportCapacityCharge,   $importCapacityExceeded,
        $exportCapacityExceeded, $genCredit,
        $genCreditCapacity,      $importCapacityScaled,
        $SuperRedRateFcpLric,    $activeCoincidence,
        $hoursInRed,
    );

    $model->summary( $tariffs, $revenue, $previousChargeImport, $importCapacity,
        $activeCoincidence, $charges1, );

    $model;

}

1;