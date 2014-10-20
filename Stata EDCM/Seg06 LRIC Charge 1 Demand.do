* Copyright licence and disclaimer
* 
* Copyright 2012-2014 Reckon LLP, Pedro Fernandes and others. All rights reserved.
* 
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are met:
* 
* 1. Redistributions of source code must retain the above copyright notice,
* this list of conditions and the following disclaimer.
* 
* 2. Redistributions in binary form must reproduce the above copyright notice,
* this list of conditions and the following disclaimer in the documentation
* and/or other materials provided with the distribution.
* 
* THIS SOFTWARE IS PROVIDED BY AUTHORS AND CONTRIBUTORS "AS IS" AND ANY
* EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED. IN NO EVENT SHALL AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
* THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

***************
*File: 4 LRIC Charge 1 Demand
*Aim: Calculate LRIC charge 1 - covers (a) super red rate LRIC , (b) local capacity charge 1 LRIC and (c) LRIC exceed capacity charge
***************

***************
*Datasets used:
*913
*913_vCluster
*953_v1_LRIC
*11
***************

***************
*Programs invoked:
*BlankToZero
*CheckZero
***************

*1. Merge 913 with 913_vCluster.dta (Generated by file "3 Linkages.do") so that can identify locations that are within same clusters

clear
set type double
use 913

*Replace negative charges with 0
replace t913c4=0 if t913c4<0
replace t913c5=0 if t913c5<0

*drop if t913c1=="Not used"

sort company t913c1

merge company t913c1 using 913_vCluster

sort company t913c1
replace st_cluster="Ind"+string(_n) if st_cluster==""

sort st_cluster
egen cluster=group(st_cluster)

*2. Calculate cluster power factor

by company cluster, sort: egen cluster_MaxDemand_kW = sum(t913c8)

by company cluster, sort: egen cluster_MaxDemand_kVAr = sum(t913c9)

gen cluster_MaxDemand_kVA=(cluster_MaxDemand_kW^2+cluster_MaxDemand_kVAr^2)^0.5

gen cluster_PowerFactor=-cluster_MaxDemand_kW/cluster_MaxDemand_kVA if cluster_MaxDemand_kVA~=0
replace cluster_PowerFactor =1 if cluster_MaxDemand_kVA==0
replace cluster_PowerFactor =1 if cluster_PowerFactor ==0

*Adjustment to reflect case where location is generation dominated

replace cluster_PowerFactor =1 if cluster_MaxDemand_kW>0

*3. Calculate weights - which are in terms of kVA - to use to calculate weighted charge 1 and then weighted charges
*If all weights within cluster are 0 then use unweighted average; this requires creating variable to check whether all weights are 0

gen Max_Demand_kVA=((t913c8)^2+(t913c9)^2)^.5

by company cluster, sort: egen sum_within_cluster_MaxDemand_kVA = sum(Max_Demand_kVA)

gen weighted_avg_Remote_Charge1 =.
gen weighted_avg_Local_Charge1 =.

*Launch program to calculate weighted average charges, using kVA as weights
MeanCharge1Clusters

*Calculate unweighted average

by company cluster, sort: egen avg_Local_Charge1=mean(t913c4)
by company cluster, sort: egen avg_Remote_Charge1=mean(t913c5)

gen Cluster_Remote_Charge1=weighted_avg_Remote_Charge1 if sum_within_cluster_MaxDemand_kVA~=0
replace Cluster_Remote_Charge1 = avg_Remote_Charge1 if sum_within_cluster_MaxDemand_kVA==0

gen Cluster_Local_Charge1=weighted_avg_Local_Charge1 if sum_within_cluster_MaxDemand_kVA~=0
replace Cluster_Local_Charge1 = avg_Local_Charge1 if sum_within_cluster_MaxDemand_kVA==0

rename t913c1 LRIC_Location
sort company LRIC_Location

drop _merge
save 913_v3a, replace

*4. Create dataset from 935LRIC

clear
use 935LRIC

*5. Combine with 913_v3_a

rename t935c8 LRIC_Location
sort company LRIC_Location

merge company LRIC_Location using 913_v3a

*Keeping only those locations that are in both datasets
keep if _merge==3
drop _merge
sort company LRIC_Location

save Combined_v3a, replace

*6. Match with data on number of hours in super-red time band in year

clear
use 11.dta
keep company t1113c1 t1113c3
sort company

merge company using Combined_v3a
keep if _merge==3

CheckZero t1113c3
gen LRICSuperRedRate=((Cluster_Remote_Charge1/cluster_PowerFactor)/t1113c3)*100

CheckZero t1113c1
gen LRICLocalCharge1=Cluster_Local_Charge1/t1113c1*100 

save Combined1_v3, replace

*7  - Adjust for cases with DSM agreements

gen LRICLocalCharge1Exceeded=LRICLocalCharge1
gen LRICSuperRedRateExceeded=LRICSuperRedRate

replace LRICSuperRedRate = LRICSuperRedRate *((t935c2-t935c18)/t935c2) if t935c18 ~=0&t935c2 ~=0
replace LRICLocalCharge1 = LRICLocalCharge1 *((t935c2-t935c18)/t935c2) if t935c18 ~=0&t935c2 ~=0

*8 - Replace negative charges with 0

*Note: No comment on this explicitly
replace LRICSuperRedRate = 0 if LRICSuperRedRate<0
replace LRICLocalCharge1 = 0 if LRICLocalCharge1<0

*9 - Calculating Charge 1 applied to generation

*Calculation of ChargeableExportCap and of Maximum export capacity

gen ChargeableExportCap=t935c4+t935c5+t935c6
gen MaximumExportCap=t935c3+ChargeableExportCap

*Note: Condition of MaximumExportCap==0  Set it to zero for now. Will make it blank at last stage
*Define it with a negative sign 

gen ShareChargeableExportCap=ChargeableExportCap/MaximumExportCap if MaximumExportCap~=0

*Dealing with option "lowerIntermittentCredit"

if $OptionlowerIntermittentCredit==0 {
gen CreditGenLRICTariff=-100*(t935c21*Cluster_Local_Charge1+Cluster_Remote_Charge1)*(ShareChargeableExportCap)/t1113c3 if MaximumExportCap~=0
}

if $OptionlowerIntermittentCredit==1 {
gen CreditGenLRICTariff=-100*t935c21*(Cluster_Local_Charge1+Cluster_Remote_Charge1)*(ShareChargeableExportCap)/t1113c3 if MaximumExportCap~=0
}

replace CreditGenLRICTariff=0 if MaximumExportCap==0

*Calculating generation credit in �, after rounding the credit to three-decimal places first 
gen CreditGenLRIC=(round(CreditGenLRICTariff,0.001)/100)*t935c19

*10 - Calculate revenue from LRIC demand charges

gen TariffRevLRICSuperRed=(LRICSuperRedRate/100)*t935c15*t935c2*t1113c3*(1-t935c23/t1113c3)
gen TariffRevLRICCapCharge1=(LRICLocalCharge1/100)*t1113c1*t935c2*(1-t935c22/t1113c1)

BlankToZero TariffRevLRICSuperRed TariffRevLRICCapCharge1 CreditGenLRIC

gen TariffRevLRICTot=TariffRevLRICSuperRed + TariffRevLRICCapCharge1
by company, sort: egen LRICRevenue=sum(TariffRevLRICTot)

*11. Calculate sum of generation super-red credits
by company, sort: egen AggLRICSuperRedGenCredit=sum(CreditGenLRIC)

drop _merge
ren app appLRIC
sort company line
save LRICCharge1Final, replace 

*10. Keep dataset just with revenue

sort comp
keep if company~=company[_n-1]
keep company LRICRevenue AggLRICSuperRedGenCredit
sort company
save LRICRevenue, replace

*Erase temporary data files

erase 913_v3a.dta
erase Combined_v3a.dta
erase Combined1_v3.dta

***************
*Data files kept:
*LRICCharge1Final
*LRICRevenue = revenue of LRIC super-red and capacity charge 1
***************