my $b;

open ($a,'>>',\$b) or die("of");
print $a "ceva";
close $a;

print $b;
