use warnings;
use strict;
use threads;
use threads::shared;

use Tk;

my $mw = new MainWindow;    
my $h;
$h=&share({});
 
 share $h->{time};
 $h->{time} = time();
 
 my  $t;
 share $t;
 $t=time();
 
#my $label = $mw->Entry(-textvariable => \$h->{time})->pack();
my $label = $mw->Entry(-textvariable => \$t)->pack();

threads->new(sub{   print "here";
#    sleep(5);
#    {
#        lock($t);
        $t = time() while(1);
#    }

#    sleep(5);
#    $h->{time} = time();
#    sleep(5);
#    $h->{time} = time();
})->detach();
    
#$mw->repeat(1000, sub{ $h->{time} = time(); } );
MainLoop;

 


