use Clone qw(clone);
use Data::Dumper;

print "cloning ref\n";

my $s->{3}="2";
print Dumper($s)."\n";
my $c=clone($s);
print Dumper($c)."\n";
$c->{3}=3;
print Dumper($c)."\n";
print Dumper($s)."\n";

print "NO f clone to value assign\n";
my $cc=clone($s);
my %cc1=%{$cc};
print Dumper(%cc1)."\n";