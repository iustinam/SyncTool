use strict;
use warnings;
use  IO::Socket;


if(not $ARGV[0]){
    die("Please specify this.pl [port] for the service\n");
}

my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $ARGV[0],
                                  Proto => 'tcp',
                               )                
	or print   "Couldn't connect to  \n";   
   
	
	select($socket);
    $|=1;
    select(STDOUT);
	print   "sending message to service..";
	syswrite($socket,"1");
	print   "sent.\n";
	close $socket;