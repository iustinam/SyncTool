use Win32::FileSecurity qw(Get EnumerateRights);
use strict;
use warnings;
use Storable qw/nstore retrieve/;
use Data::Dumper;
use Test::Deep;

##foreach( @ARGV ) {
##    next unless -e $_ ;
##    if ( Get( $_, \%hash ) ) {
##        while( ($name, $mask) = each %hash ) {
##            print "$name:\n\t";
##            EnumerateRights( $mask, \@happy ) ;
##            print join( "\n\t", @happy ), "\n";
##        }
##    }
##    else {
##        print( "Error #", int( $! ), ": $!" ) ;
##    }
##}
#my $hash1={};
#my $hash2={};
#print $ARGV[0];
#if($ARGV[0]~~"put"){
#    Get( "testfile.txt", $hash1 ) or  die "Cannot get perms\n";
#    nstore $hash1,"stored";
#}
#
#if($ARGV[0]~~"get"){
#    Get( "testfile.txt", $hash1 ) or  die "Cannot get perms\n";
#    $hash2=retrieve("stored");
#    print Dumper($hash1);
#    if (eq_deeply($hash1, $hash2)){
#      print "they match"
#    }
#}

 use Win32::Security::ACL;
my $acl_string;
my $acl =  Win32::Security::ACL->new('FILE', $acl_string);
print $acl_string;