use strict;
use warnings;
use File::Spec::Unix qw/catfile/;
use File::Copy "cp";

my $out;
my $debug_file="deg";
my $a;
#close STDERR;
#	open ($a,'>>',$debug_file) or die("of");
#        open STDERR,'>',$debug_file or print "err: cannot open STDOUT to $debug_file :$! \n";
#	select(STDERR);
#	close STDERR;      
#        $|=1; 
#	select(STDOUT);

if(system("cp","-a",File::Spec::Unix->catfile("/dev","log"),"log")){
#if(File::Copy->copy(File::Spec::Unix->catfile("/dev","log"),"log")){
#if(cp(File::Spec::Unix->catfile("/dev","log"),"log")){
#$out=`cp /dev/log log`;
#if($out){
	print "nok error is: $!$?\n\n";
#	print $debug_file;
#	open(H,'<',$debug_file) or die ("cannot open deg\n");	
#	while(<H>){print "$_";}
#	close H;
#	print "###\n";
#	print STDERR "##err\n";
}else{
print "ok; err:$!$?\n\n";
}


if(system("cp",File::Spec::Unix->catfile("/dev","sda"),"log")){
        print "nok error is: $!$?\n\n";
#	print $debug_file;
#        open(H,'<',$debug_file) or die ("cannot open deg\n");
#        while(<H>){print "$_";}
#	close H;
#	print "###\n";
}else{
print "ok; err:$!$?\n\n";
}
