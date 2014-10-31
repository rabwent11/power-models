package CDCM::PickBest;

use warnings;
use strict;
use POSIX;

sub score {

    my ( $class, $rule, $metadata ) = @_;
    my $month = $metadata->[1] || strftime( '%Y-%m', localtime );
    my $score = 0;

    # DCP 130
    $score += 100 if $rule->{tariffs} =~ /dcp130/i xor $month lt '2012-10';

    # DCP 163
    $score += 50 if $rule->{tariffs} =~ /dcp163/i xor $month lt '2013-10';

    # DCP 179
    $score += 100 if $rule->{tariffs} =~ /pc34hh/i xor $month lt '2014-10';

    # DCP 161
    $score += 100
      if $rule->{unauth}
      && $rule->{unauth} =~ /dayotex/i xor $month lt '2015-10';

    warn join ' ', $rule->{nickName} || $rule->{'.'} || $rule, $month, $score;

    $score;

}

1;