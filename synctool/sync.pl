use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Carp;                  # prints stack trace
use File::Spec;            # fs path portability
use Win32::File;           #GetAttributes and SetAttributes
use File::Copy;
use Digest::MD5;
use POSIX qw(strftime);    #time in logs
use threads;
use threads::shared;
use Thread::Queue;
use IO::Socket;
use Storable qw(lock_nstore lock_retrieve);
use Win32;
use Regexp::Assemble;
use XML::Simple;
use Filesys::DfPortable;


#use Time::HiRes qw( time); # import time function with miliseconds, else our log hash will be stored more than 10 times in a sec...

# 2 ways to start: gui/service 
# 3 ways to stop: normal finish/killed by gui + external event (uncontrolled)

my $gui_port="1313";
my $portfile:shared;
my $done:shared; # control threads that stop this process
my $job_done:shared;    #notify when task is complete
my $port:shared;   #name for portfile and port on which we expect messages from gui
my $send_stats:shared;
my $send_stats_socket;

my ($thr_worker, # runs the sync 
$thr_sync_joiner,    #waits for sync to complete normally(sets $done=1) unless stopped by gui.
$thr_stats2file,    #writes statistics every second while $done=0; (avoid 
$thr_wait_socket,   #wait message from gui (type 2 :asking statistics)
$thr_stats2sock,    #send message to socket
$thr_start_n_waitsock,
);
 # parent thread will remain blocked reading from socket (when recv "exit" msj ,set $done=1)
my $gui_on=0;   #we know that gui exists if we were asked to send stats. if set to 1 , send msj1 (exit) when finishing normally.
my $stderrs;    #variable to hold out STDERR output if --gui set
my $last_action_add=0; #prevent logging "ALT" actions if an ADD was made previously>> keep log simple
my $script_start_time=time; # when writing stats file, calculate total duration

my %opt = ();
my @job_logs;
my $log_file;      #contains every file scanned
my $stats_file:shared;           #contains statistics such as # files scanned/deleted/copied, #bytes copied , etc.
my $src:shared; # needed for drop_stats thread, which writes to file (opt{s} is initialized in child thread)
my $dst:shared;
my $logh;
my %log:shared;                   #hash ref to log types (statistics)
my @exclude_list;   #list of exact file names
my @exclude_list_re;
my $excl_re;    #combined regex to match all excluded patterns

my $debug_file;    # filled when -v option is set
#my $dbh;
#my $verbose; #used by thread 0 to know if verbose was set (thread 1 initializes %opt)

#my $q=Thread::Queue->new();
#my $store_file="D:/sync1/stored";

my (
    $action_start,         
    $timer,                #use for vrfy actions \
    $v_size,               #calculating bytes copied/deleted
    $v_start,$v_elapsed,
    $s_attr,$d_attr        #used for alterind attributes
);

my $xml="C:\\synctool\\conf.xml";
my $paths=XMLin($xml);

use constant {
    #STAT_WR_SLEEP => 3,
    #LOG_FOLDER => $paths->{running_folder},
    #PORFILE_FOLDER => $paths->{running_folder},
    ERR_FILE => 'D:/sync1/errors.txt',

# number of threads in pool for syncing simultaneously at a given moment in time
    DIR_THR_NO => 10
};

my $running_folder=$paths->{running_folder};
$running_folder =~ s!/$!!;
my $LOG_FOLDER =$running_folder."\\Logs\\";
my $PORFILE_FOLDER = $running_folder."\\Logs\\";
if(not -d $LOG_FOLDER){
 mkdir $LOG_FOLDER or print "sync: err: creating $LOG_FOLDER\n";
}
my $STAT_WR_SLEEP = $paths->{touch_portfile_time};

# items action types
# DEL ADD ALT REPL (SKIP *) EXCL

###########################################################################

&main(@ARGV);

###########################################################################

sub usage {
    ( my $pl_file = $0 ) =~ s!.+/!!;    # perl file name , removed path
    print STDOUT << "EOF";

    usage: $pl_file -s source_dir -d dest_dir {-sid number(not 0) -did number(not0) | -nogui } [-c {1|2|3|4}] [-exclre "pttn1","pttn2".. ] [-excl "filename1","filename2",..]
     -h             : this (help) message
     -v             : verbose mode 
     -sid           : source id (needed to create portfile [sid].[did].[port].portfile and socket communication). Mandatory unless -nogui was specified.
     -did           : destination id. Mandatory unless -nogui was specified
     -nogui         : if set, portfile will not be created, therefore no socket communication with gui.pl will take place
     -gui           : do not use. (Used by gui.pl when calling this script to force it to send stats immediately)
     -excl          : exclude list, NO regex. Ex: ' -excl "my file.txt",picture.png '
     -exclre        : exclude everything that contains any of the patterns given: ' -exclre ".txt","test" '
     -c {1|2|3|4}   : copy mode (using system(copy..)[1], File::Copy[2], system(xcopy..)[3], Win32::CopyFile[4] (DEFAULT)
     -md5           : do md5 check on each file copied (very slow, untested recently).

     
    example: perl $pl_file  -s s -d d -sid 13 -did 14 -exclre ".txt",".tmp" -excl "thumbs.db" -nogui
EOF

    #exit;
    {
        lock($done);
        $done=1;   
    }
    #croak "Bye.--------------------------------------------------------\n";
    threads->exit();
}

###########################################################################
sub list {
    my $dir = shift @_;
    $dir =~ s!/$!!; #remove trailing slash  
    #print  "2 $dir \n";
    opendir( DIR, $dir ) || die "err: opendir failed: $!";
    #print  "3 $dir\n"; 

    #        grep not current dir or parent ( . and .. )
    my @ls = grep !/\.\.?$/, readdir(DIR);
    closedir DIR;
    #print  "4\n"; 
#    print Dumper(@ls)."\n-\n";
#    my %temp= map {$_=>1} @ls;
#    foreach(@exclude_list){
#        if($temp{$_}){
#            delete $temp{$_};
#        }   
#    }
#    @ls=keys %temp;
#    print Dumper(@ls)."\n-------\n";

    my @ret;
    
#    my %h1=map {$_ =>1} @ls;
#    my %h2=map {$_ =>1} @exclude_list_re;
#    my %h3=map {$_ =>1} @exclude_list;
#    my @ls1=keys %{{%h1,%h2}};
#    foreach(@ls1){
#        #in dir,not in excl
#        #in dir,in excl
#        #not in dir,in excl   
#        if(($h1{$_}&&$h2{$_})||($h2{$_}&&${grep/$_/,@ls})){
#            delete $h1{$_
#        }
#    }
    #print "all ".Dumper(@ls);
    #filter out everything that contains smth from exclude regex list 
    @ret=grep !/($excl_re)/,@ls;
    #print "without exclre ".Dumper(@ret);
    my %del=map{$_=>1} @exclude_list;
    @ret=grep !$del{$dir."\\".$_},@ret;
    #print "filtered ".Dumper(@ret);
    
    
    return @ret;
}
###########################################################################

# keep attr, fs independent, mode set
# ret 0 for success
sub copy_one {
    my ( $s_path, $d_path ) = @_;
    my $copy_choice = ( defined $opt{c} ) ? $opt{c} : 4;
    my $ret;
    
     my $ref = dfportable($opt{d});
     if(defined($ref)) {
         # warn if space on dest falls below 100KB
         if(($ref->{bfree}-(stat($s_path))[7])<  100000){
             print $logh "\n!Warning! Free space available on destination is $ref->{bfree} \n";
             print "Warning! Free space available on destination is $ref->{bfree} ";
             &die_fast();
             threads->exit();
         }
     }else{
         #? 
         print "sync: warn: cannot check free space\n"; 
     }

    #print "choice $copy_choice\n";
    #print "$s_path ==> $d_path\n";

    if ( $^O =~ /win/i ) {
        if ( $copy_choice == 1 ) {
            # system rets 0 on success
            if ( system( 'copy', "\"$s_path\"", "\"$d_path\"" ) ) {
                #croak "err: $!\n";
                $ret = 1;
            }else {
                $ret = 0;
            }
        } elsif ( $copy_choice == 2 ) {
            # rets 1 on success
            if ( File::Copy::copy( $s_path, $d_path ) ) {
                $ret = 0;
            }else {
                #croak "err:$!\n";
                $ret = 1;
            }
        } elsif ( $copy_choice == 3 ) { #user interactive.. can't disable
            # rets 0 on success
            if ( system( 'xcopy','/H','/F', "\"$s_path\" ", "\"$d_path\"" ) ) {
                $ret = 0;
            }else {

                #croak "err:$!\n";
                $ret = 1;
            }
        } elsif ( $copy_choice == 4 ) { #!!!!!!!!!!!!!!!!!!!!!!
            # rets 0 on success
            if ( Win32::CopyFile($s_path, $d_path,0) ) {
                $ret = 0;
            }else {

                #croak "err:$!\n";
                $ret = 1;
            }
        }
    } else {
        print  "noth\n" if($opt{v});
    }

    if($opt{md5}){
        print  "#testing md5.." if($opt{v});
        if ( ( md5($s_path) ne md5($d_path) ) && $opt{v} ) {
            print  "..err:$!\n" if($opt{v});
            $ret = 1;
        } else {
            print  "..ok\n" if($opt{v});
            $ret = 0;
        }
    }
    return $ret;
}
###########################################################################

# del a directory tree , recursively, using unlink and rmdir
# ret 0 for success
# todo need to pass a string too.logg? no.need action_start
sub rm_tree {
    my ($path,$is_root) = @_;
    my $ret;
    
    $action_start=time;
    print  $path. "\n" if($opt{v});
    if ( -d $path ) {
        &update_log("D","SCAN",1);

        print  "is dir..listing $path\n" if($opt{v});
        &rm_tree( File::Spec->catfile( $path, $_ ),0 ) foreach &list($path);
        print  "is dir..rem empty $path\n" if($opt{v});
        
        # before we remove any dir, FIRST UNSET ANY ATTRIBUTES, especially read-only stuff
        if(not Win32::File::SetAttributes($path,NORMAL)) {
            print  "err: unsetting attr for dir $path: $! \n" if($opt{v})
        }
        if ( rmdir $path ) {    #success
            #noth;
            if($is_root){
                logg( $path, "D", "DEL", $action_start, time - $action_start );
            }else{
                &update_log("D","DEL",1);
            }
            #print "rem\n";

        } else {    #err #no need to continue, error would be propagated
            print  "err: rmdir $path $!\n" if($opt{v});
            logg( $path . ": Rmdir: $!","D", "SKIP_DEL", $action_start, time - $action_start );

            return 1;
        }
    } elsif ( -f $path ) {
        #$q->enqueue("1");
        &update_log("F","SCAN",1);

        print  "is file\n" if($opt{v});
        $v_size = -s $path;

        # use of action start?
        if ( unlink($path) ) {    #success
            &update_log("F","DEL",1);
            &update_log("KB","DEL",$v_size);

            #noth
        } else {                    #err #need to know where it crashed
            logg( $path . ": Unlink: $!", "F", "SKIP_DEL", $action_start, time - $action_start );
            return 1;    #no need to continue, error would be propagated
        }
    } else {
        if ( $opt{v} ) { print "err: unknown type $path $!\n"; }
        logg( $path . ": Unknown type: $!","U", "SKIP_U", $action_start, time - $action_start );
        return 1;
    }
    return 0; #success
}
###########################################################################

###########test
# returns md5 of a file
sub md5 {
    &update_log("F","MD5",1);
    
    $timer = time;       

    my ($f) = shift;
    open( FH, '<', $f ) or return ("");
    binmode(FH);
    my $ret = Digest::MD5->new->addfile(*FH)->hexdigest();
    close FH;
    
    &update_log("TIME","MD5",time - $timer);
    return $ret;
}

###########################################################################

# store in a list/file
# format: pathname type action starttime elapsedtime
sub logg {
    my ( $pathname, $type, $action, $start, $elapsed ) = @_;
    push @job_logs,
      {
        PATH    => $pathname,
        TYPE    => $type,
        ACTION  => $action,
        STARTED => $start,
        ELAPSED => $elapsed
      };
      
    if($last_action_add&&($action eq "ALT")){
        $last_action_add=0;
        update_log("TIME",$action,$elapsed);
        update_log("TIME","ALL",$elapsed);
    }else{
        update_log($type,$action,1);
        update_log("TIME",$action,$elapsed);
        update_log("TIME","ALL",$elapsed);

        # constant saving to logfile
        $v_start =POSIX::strftime( "%H:%M:%S %d/%m/%y", localtime( $start ) );
        $v_elapsed = (gmtime($elapsed))[2].":".(gmtime($elapsed))[1].":".(gmtime($elapsed))[0];   #POSIX::strftime( "%H:%M:%S", localtime($elapsed)  );
        print $logh pack( "A19 A9 A5 A10 A*",
            $v_start, $v_elapsed, $type, $action, $pathname )
          . "\n";
    }
}
###########################################################################

# updates %log for key and value
my $now=1;
sub update_log{
    my ($key1,$key2,$val)=@_;
    
    {
        lock(%log);
        $log{$key1}{$key2}+=$val;
    }
    if(time%5 eq 0){
        if($now){
#            if($send_stats){
#                my $stats=$opt{sid}."_".$opt{did}."_".$log{TIME}{ALL};    
#                print "sync $port: send_stats2sock: sending $stats\n";
#                syswrite($send_stats_socket,$stats);
#            }
#            if($portfile){
#                lock_nstore \%log,$portfile;
#                print "sync $port: stored..\n";
#            }
            $now=0; 
        }   
    }else{
        $now=1;   
    }
}
###########################################################################

# this includes the case when a file was deleted from source and
# simple checking for item type (file/dir), in ww we cannot have a dir and a file with the same name in the same location \
# if item is neither file/dir we DIE.
sub sync {
    my ( $src, $dst ) = @_;    # full path dirs
                               #print $src;
    
    my %s_list = map { $_ => 1 } &list($src); 
    my %d_list = map { $_ => 1 } &list($dst); 

#print  "1\n"; ###NU IL SCRIE !!!
    # hash keeping unique name entries existent either in source or destination
    my @all = keys %{ { %s_list, %d_list } };   # easier to enumerate the possible cases

    foreach my $item ( sort @all ) {
        print  "----------------------------------------------------------------\n" if $opt{v};
        
        my $s_path = File::Spec->catfile( $src, $item );
        my $d_path = File::Spec->catfile( $dst, $item );

        $action_start = time;

        if ( -d $s_path ) {    # item exists in src dir and is a directory
            if ( !-d $d_path ) {    # item is not a dir in dst
                if ( -f $d_path ){ # item is a file in dst >>delete it from dest since we must copy the dir over it
                    &update_log("F","SCAN",1);

                    print  "$s_path: dir to file, deleting dest file\n" if($opt{v});
                    $v_size = -s $d_path;
                    if ( unlink($d_path) ) {    #success
                        &update_log("KB","DEL",$v_size);

                        print  "$s_path: OK dir to file, deleting dest file\n" if($opt{v});
                        logg( $d_path, "F", "DEL", $action_start, time - $action_start );
                    }else {                      #err
                        print  "$s_path: ERR dir to file, deleting dest file\n" if($opt{v});
                        logg( $d_path . ": Unlink: $!","F", "SKIP_DEL", $action_start, time - $action_start );
                    }
                }elsif ( $d_list{$item} ){ # item is neither a file or dir but exists in dst (dir in src)>>skip
                    print  "$d_path: ERR unknown item type\n" if($opt{v});
                    logg( $d_path . ": Unknown type", "U", "SKIP_U", $action_start, time - $action_start );
                }

                # item does not exist in dst >> create this dir (dir in src)
                print  "$s_path: creating dest dir\n" if($opt{v});
                if ( mkdir $d_path ) {
                    print  "$s_path: OK created dest dir\n" if($opt{v});
                    logg( $d_path, "D", "ADD", $action_start, time - $action_start );
                    $last_action_add=1;
                }else {
                    print  "$s_path: ERR creating dest dir\n" if($opt{v});
                    logg( $d_path . ": mkdir: " . $!,"D", "SKIP_ADD", $action_start, time - $action_start );
                }
            }
            
            if(not $last_action_add){
                # item is already a dir in dst ( dir in src too) >> recursion
                &update_log("D","SCAN",1);
            }

            if ( $opt{v} ) {print  "# set attributes for dir $d_path (src)$s_path if they differ\n" if($opt{v});}
            Win32::File::GetAttributes( $s_path, $s_attr );
            Win32::File::GetAttributes( $d_path, $d_attr );
            if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                if ( $opt{v} ) {
                    print  "attrs for dirs differ.." if($opt{v});
                }
                Win32::File::SetAttributes( $d_path, $s_attr );

                # test if attr were set properly
                Win32::File::GetAttributes( $d_path, $d_attr );
                if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                    if ( $opt{v} ) { print "alt failed\n"; }
                    logg(  $d_path . ": Altering attributes: " . $!,"D", "SKIP_ALT", $action_start, time - $action_start );
                } else {
                    if ( $opt{v} ) { print  "alt ok\n" if($opt{v}); }
                    logg( $d_path, "D", "ALT", $action_start,time - $action_start );
                }
                
            }
            $last_action_add=0;
            
            print  "-----------\n" if($opt{v});
            sync( $s_path, $d_path ) if (-d $d_path); #if err occured when mkdir
        }
        elsif ( -f $s_path ) {    # item exists in src dir and is a file
            #if ( $d_list{$item} ) {    # item exists in dst
                if ( -d $d_path ) {    # item is a dir in dst (file in src)
                    #&update_log("D","SCAN",1); #done in rm_tree

                    print  "$s_path: file over dir\n" if($opt{v});
                    if ( rm_tree($d_path,1) ) {    #err
                        print  "$s_path: ERR rmtree file over dir\n" if($opt{v});
                        #logg(  $d_path . ": Deleting tree: " . $! ,"D", "SKIP_DEL", $action_start,time - $action_start );     #done in rm_tree
                    } else {                       #success
                        print  "$s_path: OK rmtree file over dir\n" if($opt{v});
                        #logg( $d_path, "D", "DEL", $action_start, time - $action_start );  #done in rm_tree
                    }
                    if ( copy_one( $s_path, $d_path ) ) {    #fail
                                                             # copy failed
                                                             # ? err kept?
                        logg( $d_path . ": " . $! , "F", "SKIP_ADD", $action_start,time - $action_start ); 
                    } else {                                   #success
                        &update_log("KB","ADD",-s $d_path);
                         
                        logg( $d_path, "F", "ADD", $action_start,time - $action_start );
                    }
                } elsif ( -f $d_path ) {    # item is file in dst (file in src) >> check ATTR
                    &update_log("F","SCAN",1);
#                        print $item."\n";
#                       print $s_list{$item}."\n";
#                       print $d_list{$item}."\n";

                    print  "$s_path: both file are here, checking mtime and size\n" if($opt{v});

                    &update_log("F","VRFY",1);
                    $timer = time;

                    ##### mtime and size
                    #print "!!! $d_path \n";
                    if ( ( -M $s_path != -M $d_path ) or ( -s $s_path != -s $d_path ) ){
                        &update_log("TIME","VRFY",time - $timer);
                        print  "$s_path: replacing file\n" if($opt{v});

                        $v_size = -s $d_path;    #log
                        if ( unlink($d_path) ) {
                            #logg( $d_path, "F", "DEL", $action_start, time - $action_start ); #do not log del before repl
                            &update_log("KB","DEL",$v_size);
                            &update_log("TIME","DEL",time-$action_start);
                            &update_log("TIME","ALL",time-$action_start);
                            
                        } else {
                            logg( $d_path . ": Unlink: $!","F", "SKIP_DEL", $action_start, time - $action_start );
                        }
                        if ( copy_one( $s_path, $d_path ) ) {

                            # copy failed
                            # ? err kept?
                            logg( $d_path . ": Copy: " . $!, "F", "SKIP_REPL", $action_start, time - $action_start );
                        } else {
                            &update_log("KB","REPL", -s $d_path);
                                
                            logg( $d_path, "F", "REPL", $action_start, time - $action_start );
                            $last_action_add=1;
                        }
                    } else {
                        &update_log("TIME","VRFY", time - $timer);
                    }
                    print  "#either copied or not, we must check the attrs. and sync them too\n" if($opt{v});
                    Win32::File::GetAttributes( $s_path, $s_attr );
                    Win32::File::GetAttributes( $d_path, $d_attr );
                    if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                        Win32::File::SetAttributes( $d_path, $s_attr );

                        # test if attr were set properly
                        Win32::File::GetAttributes( $d_path, $d_attr );
                        if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                            if ( $opt{v} ) { print "attrs differ\n"; }
                            logg(  $d_path . ": Altering attributes: " . $! , "F", "SKIP_ALT",$action_start,time - $action_start);
                        } else {
                            if ( $opt{v} ) { print "attrs same\n"; }
                            logg( $d_path, "F", "ALT", $action_start,time - $action_start );
                        }
                    }
                    $last_action_add=0;

                }  elsif($d_list{$item}) {    # item is dunno what in dst (file in src)>>skip
                    print  "err: unknown item $d_path" if($opt{v});

                    # noth
                    logg( $d_path . ": Unknown type",  "U", "SKIP_U", $action_start, time - $action_start );
                
            } else {    # item does not exist in dst >> copy this file in dst too
#                print Dumper(%d_list)."\n ".lc($item)."\n";
#                my $it=lc($item);
#                if($d_list{$it}){print "ok " }else{print "nok";};
                
                print  "$s_path: copying new file\n" if($opt{v});
                if ( copy_one( $s_path, $d_path ) ) {    #fail
                    logg(  $d_path . " " . $! , "F", "SKIP_ADD", $action_start, time - $action_start ); 
                } else {                                   #success
                    &update_log("KB","ADD",-s $d_path);
                       
                    logg( $d_path, "F", "ADD", $action_start,time - $action_start );
                    
                    # change attrs too
                    Win32::File::GetAttributes( $s_path, $s_attr );
                    Win32::File::GetAttributes( $d_path, $d_attr );
                    if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                        Win32::File::SetAttributes( $d_path, $s_attr );

                        # test if attr were set properly
                        Win32::File::GetAttributes( $d_path, $d_attr );
                        if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {
                            if ( $opt{v} ) { print "attrs differ\n"; }
                            logg(  $d_path . ": Altering attributes: " . $! , "F", "SKIP_ALT",$action_start,time - $action_start);
                        } else {
                            if ( $opt{v} ) { print "attrs same\n"; }
                            #logg( $d_path, "F", "ALT", $action_start,time - $action_start ); # don't log alt is add was made
                        }
                    }
                }
            }
        } elsif ( $s_list{$item} ) {    # item exists in src dir but is neither a dir or a file >> skip
            print  "err: unknown item $s_path" if($opt{v});

            # noth
            logg( $s_path . ": Unknown type","U", "SKIP_U", $action_start, time - $action_start );
        } elsif ( -f $d_path ) { # item exists in dest and is a file (item does not exist in src) >>delete file
            &update_log("F","SCAN",1);
               
            print  "$d_path: deleting dest file\n" if($opt{v});
            $v_size = -s $d_path;
            if ( unlink($d_path) ) {
                &update_log("KB","DEL",$v_size);
                logg( $d_path, "F", "DEL", $action_start,time - $action_start );
            } else {
                logg( $d_path . ": Unlink: $!","F", "SKIP_DEL", $action_start, time - $action_start );
            }
        } elsif ( -d $d_path ) { # item exists in dest and is a dir (item does not exist in src) >>delete tree
            #&update_log("D","SCAN",1); #already in rm_tree

            print  "$d_path: deleting dir\n" if($opt{v});
            if ( rm_tree($d_path,1) ) {    #err
                print  "err rm_tree\n" if($opt{v});
                #logg( $d_path . ": deleting tree: " . $! , "D", "SKIP_DEL", $action_start, time - $action_start ); #already in rm_tree
            } else {                       #success
                #logg( $d_path, "D", "DEL", $action_start,time - $action_start );   #already in rm_tree
            }
        } else { # item is neither a file or a dir and it belongs to dst children (item does not exist in src) >> skip 
            print  "err: unknown item $d_path" if($opt{v});

            # noth
            logg( $d_path . ": Unknown type", "U", "SKIP_U", $action_start, time - $action_start );
        }
    }
}
###########################################################################

sub die_fast{
    print   "----".threads->self()->tid()." Stopping everything..\n";
    while(!$port) {sleep(1);}
     my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $port,
                                  Proto => 'tcp',
                               )                
	or print "gui: Couldn't connect to $port to stop \n";   
    select($socket);
	$|=1;
	select(STDOUT);
	my $msj_1="1";
	syswrite($socket,$msj_1);
	close $socket;
}
###########################################################################

sub init {
    $done=0; $|=1;
    #getopts( "hvc:", \%opt ) or &usage;
    GetOptions(
        "s=s" => \$opt{s},
        "d=s" => \$opt{d},
        "h"   => \$opt{h},
        "v"   => \$opt{v},
        "c=i" => \$opt{c},
        "md5" => \$opt{md5},
        "sid=i" => \$opt{sid},   # source id 
        "did=i" => \$opt{did},    # dest id , used for log file naming and identification during messaje exchanges with gui.
        #"p=i"=> \$opt{port},    # portfile tells gui that we are alive
        "gui" => \$opt{gui},
        "excl=s" => \@exclude_list, #must look like " -excl \\a\b\c,\\b,\\d\s\a, "
        "exclre=s" => \@exclude_list_re,
        "nogui" => \$opt{nogui},
      )
      or &usage;
      
    {
        lock($src);
        $src=$opt{s};  
    }
    {
        lock($dst);
        $dst=$opt{d};   
    }
    
    @exclude_list=split(/,/,join(',',@exclude_list));
    #print Dumper(@exclude_list);
    
    @exclude_list_re=split(/,/,join(',',@exclude_list_re));
    #print Dumper(@exclude_list_re);
    $excl_re=Regexp::Assemble->new->add(@exclude_list_re);
    #print $excl_re->re."\n";
    
    #die();
    
    if ( $opt{h} ) { &usage; }
    
    my $sid=$opt{sid}?$opt{sid}:"sid";
    my $did=$opt{did}?$opt{did}:"did";
    
    $debug_file=$LOG_FOLDER.$sid."_".$did.POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".debug";
    
    if($opt{v}){
        #redirect stdout
        close STDOUT;
        open STDOUT,'>',$debug_file or print "err: cannot open STDOUT to $debug_file :$! \n";
        select(STDOUT);
        $|=1; 
        print "opened\n";
    }
    
    if ( !($opt{s} and $opt{d}) ) {
        print "Please specify source and destination!\n-------------------------------------\n";
        &usage;
    }
    if (!(($opt{sid} and $opt{did})||$opt{nogui})){
        print "Please specify sid and did!\n-------------------------------------\n";
        &usage;
    }
    if ( ( !-d $opt{s} ) || !-d $opt{d} ) {
        print "Make sure source and destination are directories\n";
        usage;
    }

    # init structures for logging
    # autovificate this tree
    
    
    {
        lock(%log);
        $log{F}=&share({});
        $log{D}=&share({});
        $log{TIME}=&share({});
        foreach (qw(ADD ALT DEL SKIP_U SKIP_DEL SKIP_ADD SKIP_ALT )) {
            share $log{F}{$_};
            share $log{D}{$_};
            share $log{TIME}{$_};
        
            $log{F}{$_}    = 0;
            $log{D}{$_}    = 0;
            $log{TIME}{$_} = 0;
        }
        share $log{F}{VRFY};
        share $log{F}{MD5};
        share $log{F}{REPL};
        share $log{F}{SKIP_REPL};
    
        share $log{F}{SCAN};
        share $log{D}{SCAN};

        $log{KB}=&share({});
        share $log{KB}{ADD};
        share $log{KB}{REPL};
        share $log{KB}{DEL};

        share $log{TIME}{REPL};
        share $log{TIME}{SKIP_REPL};
        share $log{TIME}{MD5};
        share $log{TIME}{VRFY};
        share $log{TIME}{ALL};

        $log{F}{VRFY} = 0;    ## for files present both in src and dest
        $log{F}{MD5}  = 0;    ##
        $log{F}{REPL} = 0;
        $log{F}{SKIP_REPL} = 0;
    
        $log{F}{SCAN} = 0;    ## destination files
        $log{D}{SCAN} = 0;    ## destination dirs

        $log{KB}{ADD}  = 0;   ##
        $log{KB}{REPL} = 0;   ##
        $log{KB}{DEL}  = 0;   #

        $log{TIME}{REPL} = 0; ##
        $log{TIME}{SKIP_REPL} = 0;
        $log{TIME}{MD5}  = 0; ##
        $log{TIME}{VRFY} = 0; ##
        $log{TIME}{ALL} = 0; ##
        
        
    }
    
    

    $log_file=$LOG_FOLDER.$sid."_".$did.POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".log";
    print $log_file."\n";
    {lock($stats_file);
    $stats_file=$LOG_FOLDER.$sid."_".$did.POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".stats";
    }
    
#    $debug_file=$LOG_FOLDER.$sid."_".$did.POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".debug";
#    
#    if($opt{v}){
#        #redirect stdout
#        close STDOUT;
#        open STDOUT,'>',$debug_file or print "err: cannot open STDOUT to $debug_file :$! \n";
#        select(STDOUT);
#        $|=1; 
#        print "opened\n";
#    }
    
    # shouldn;t happen unless we start it manually
    # find next available port in order to create a socket and wait for stop/getStatus messages from gui. , create portfile
#    if (!$opt{port}){
#        opendir( D, PORFILE_FOLDER) or die ("err: cannot open portfile dir: $!");
#        my @portfiles= grep /.*\.portfile$/, readdir(D);
#        closedir(D);
#        my @ports;
#        foreach(@portfiles){
#            /[0-9]+\.[0-9]+\.([0-9]+)\.portfile$/;
#            push @ports,$1;   
#        }
#        @ports= sort @ports;
#        $port=$ports[-1]+1;
#    } else{ #else assume the port was correctly chosen by gui and sent as a param.
#        $port=$opt{port};
#    }
    
    #print "created file $portfile\n";
}
###########################################################################

# params: filehandle, reference to the hash that contains the stats
sub write_stats_to_handle{
    my ($logh,$log)=@_;
    print $logh "--------------------------------------------------------------------\n";
    print $logh $src." >> ".$dst."\n";
    print $logh "Summary: Process statistics (folders): $log->{D}{ADD} folders added, $log->{D}{ALT} folders altered, $log->{D}{DEL} folders removed, $log->{D}{SCAN} folders scanned.\n";
    print $logh "Summary: Process statistics (files): $log->{F}{ADD} files added, $log->{F}{REPL} files replaced, $log->{F}{ALT} files altered, $log->{F}{DEL} files removed, $log->{F}{SCAN} files scanned. (md5 $log->{F}{MD5})(vrfy $log->{F}{VRFY})\n";
    print $logh "Summary: Process statistics (folder errors): $log->{D}{SKIP_ADD} SKIP_ADD, $log->{D}{SKIP_DEL} SKIP_DEL, $log->{D}{SKIP_ALT} SKIP_ALT, $log->{D}{SKIP_U} SKIP_U.\n";
    print $logh "Summary: Process statistics (file errors): $log->{F}{SKIP_ADD} SKIP_ADD, $log->{F}{SKIP_REPL} SKIP_REPL, $log->{F}{SKIP_DEL} SKIP_DEL, $log->{F}{SKIP_ALT} SKIP_ALT, $log->{F}{SKIP_U} SKIP_U.\n";
    print $logh "Summary: Process statistics (total errors):".eval($log->{D}{SKIP_ADD}+$log->{D}{SKIP_DEL}+ $log->{D}{SKIP_ALT}+$log->{D}{SKIP_U}+$log->{F}{SKIP_ADD}+$log->{F}{SKIP_DEL}+$log->{F}{SKIP_ALT}+$log->{F}{SKIP_U}+$log->{F}{SKIP_REPL})." \n";
    print $logh "Summary: Process statistics (KB): $log->{KB}{ADD}"." B added, $log->{KB}{REPL}"." B replaced, $log->{KB}{DEL}"." B deleted.\n";
    #print $logh "Summary: Process statistics (durations): ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{ADD}) )." for adding files, ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{REPL}) )." for file replacing, ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{ALT}) )." for altering attrs, ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{DEL}) )." for removing. (md5 ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{REPL}) )." )(vrfy ".POSIX::strftime( "%H:%M:%S", localtime($log->{TIME}{VRFY}) )." )\n";

    my $add_time=(gmtime($log->{TIME}{ADD}))[2].":".(gmtime($log->{TIME}{ADD}))[1].":".(gmtime($log->{TIME}{ADD}))[0]; 
    my $repl_time=(gmtime($log->{TIME}{REPL}))[2].":".(gmtime($log->{TIME}{REPL}))[1].":".(gmtime($log->{TIME}{REPL}))[0];
    my $alt_time=(gmtime($log->{TIME}{ALT}))[2].":".(gmtime($log->{TIME}{ALT}))[1].":".(gmtime($log->{TIME}{ALT}))[0];
    my $del_time=(gmtime($log->{TIME}{DEL}))[2].":".(gmtime($log->{TIME}{DEL}))[1].":".(gmtime($log->{TIME}{DEL}))[0];
    my $md5_time=(gmtime($log->{TIME}{MD5}))[2].":".(gmtime($log->{TIME}{MD5}))[1].":".(gmtime($log->{TIME}{MD5}))[0];
    my $vrfy_time=(gmtime($log->{TIME}{VRFY}))[2].":".(gmtime($log->{TIME}{VRFY}))[1].":".(gmtime($log->{TIME}{VRFY}))[0];
    my $skip_time=$log->{TIME}{SKIP_U}+$log->{TIME}{SKIP_DEL}+$log->{TIME}{SKIP_ADD}+$log->{TIME}{SKIP_ALT}+$log->{TIME}{SKIP_REPL};
    my $skip_time_str=(gmtime($skip_time))[2].":".(gmtime($skip_time))[1].":".(gmtime($skip_time))[0]; 
    
   # $log->{TIME}{ALL}=$log->{TIME}{ADD}+$log->{TIME}{REPL}+$log->{TIME}{ALT}+$log->{TIME}{DEL}+$log->{TIME}{MD5}+$log->{TIME}{VRFY};
    my $all_time=(gmtime($log->{TIME}{ALL}))[2].":".(gmtime($log->{TIME}{ALL}))[1].":".(gmtime($log->{TIME}{ALL}))[0];
    
    print $logh "Summary: Process statistics (durations): ".$add_time." for adding files, ".$repl_time." for file replacing, ".$alt_time." for altering attrs, ".$del_time." for removing, ".$skip_time_str." for SKIP. (md5 ".$md5_time." )(vrfy ".$vrfy_time." )\n";
    print $logh "Summary: Process completed: Total Duration For Taking Actions ".$all_time . "\n";  
    
    my $runtime=time-$script_start_time;
    my $runtime_str= (gmtime($runtime))[2].":".(gmtime($runtime))[1].":".(gmtime($runtime))[0]; 
    
    print $logh "Summary: Process completed: Total Runtime ".$runtime_str . "\n"; 
}
###########################################################################

###########################################################################

# this runs in $thr_stats2file
# statistics writer thread 
sub drop_stats{
    while(!$done){
        #print  "----".threads->self()->tid()." writing..\n";
        sleep($STAT_WR_SLEEP);
        #
        
        #touch portfile to let gui know that we are running
        if($portfile){
            open(F,'>',$portfile) or print "sync ".eval($port?$port:"").": drop_stats: err opening portfile $portfile \n";
            print F "alive";
            close F;
        } 
        #nstore $log, $stats_file;   
        my $sth;
        while(!$stats_file){ 
            #maybe we get killed before we even created a stats_file
            if($done) {
                $thr_start_n_waitsock->join();
                exit();
            }
            print   "----".threads->self()->tid()." sleeping\n";
            sleep(1);
        }
        open( $sth, '>', $stats_file ) or die "err: Cannot open stats file $stats_file \n";  #rewrite.
        
        &write_stats_to_handle($sth,\%log);
        close $sth;
        #}
        #print  "----".threads->self()->tid()." stats: end..\n";
    }
    print  "----".threads->self()->tid()." done =".$done."\n";
    
}
###########################################################################

# this is in thr_worker
# do our thing. 
sub sync_starter{
    
    $SIG{'KILL'}=sub{ print   "----".threads->self()->tid()." sync : sync thr: dying..\n";threads->exit() };
    
    open( $logh, '>>', $log_file ) or die "err: Cannot open log file $log_file \n";  #append
    #unbuffer log
    select($logh); $|=1;
    select(STDOUT);
    # nice format for log file
    print $logh pack( "A19 A9 A5 A10 A*", "STARTED", "ELAPSED", "TYPE", "ACTION", "PATH" ). "\n";
      
    &sync(@_);
    
    {
        lock($job_done);
        $job_done=1;   
    }
    
#    print "\n\nthr act: ".Dumper(threads->list(threads::running));
#    {
#        lock($done);
#        $done=1;
#    }
#    print "\n\nthr act: ".Dumper(threads->list(threads::running));
    # $thr_stats2sock might be waiting for join (if gui is up)
    
#    if($thr_start_n_waitsock){   #this is now parent
#        #$thr_stats2sock->join();   
#        print "killing \n";
#        $thr_start_n_waitsock->kill('KILL')->join();
#    }
    
    
#    # $thr_stats2file waits to be joined..  # ??? de ce nu apare ca joinable?
#    $thr_stats2file->join();
#    
#    print "\n\nthr act: ".Dumper(threads->list(threads::running));
    
    if($portfile){
        unlink($portfile) or print "sync ".eval($port?$port:"").": err: unlink $portfile \n";
        undef($portfile);
    }
    
    &write_stats_to_handle($logh,\%log);
        
    close $logh or die($!);
    
#    {
#        lock($done);
#        $done=1;
#    }
    
    ### kill parent
    print   "----".threads->self()->tid()." killing parent\n";
    while(!$port) {sleep(1);}
     my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $port,
                                  Proto => 'tcp',
                               )                
	or print "gui: Couldn't connect to $port to stop \n";   
    select($socket);
	$|=1;
	select(STDOUT);
	my $msj_1="1";
	syswrite($socket,$msj_1);
	close $socket;
    
#    my $sth;
#    # write stats also to $stats_file if we finished normally
#    open( $sth, '>', $stats_file ) or print "sync ".eval($port?$port:"").": err: Cannot open stats file $stats_file \n"; 
#    
#    &write_stats_to_handle($sth,\%log);
#    print "end\n";
#    close $sth;

    
    # write $stderrs to file
#    open (ERR, '>>', ERR_FILE) or print "sync $port: err: Cannot open stats".ERR_FILE." \n";
#    print ERR "--------------------------------------------------------------------\n\n";
#    print ERR $opt{sid}."_".$opt{did}.POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime);
#    print ERR $stderrs."\n";
#    close ERR;

#    foreach(threads->list(threads::running)){
#        if(not $_->equal(threads->self())){
#            print "killing $_->tid() \n";
#            $_->kill('KILL');   
#        }
#    }
    #threads->object("0")->kill('KILL');
    
    print   "----".threads->self()->tid()." sync_starter finishing..\n";
}
###########################################################################

sub send_stats2sock{
    my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $gui_port,
                                  Proto => 'tcp',
                               )                
	or print   "----".threads->self()->tid()." sync ".eval($port?$port:"").": send_stats2sock: Couldn't connect to $gui_port \n";   
   
	$SIG{'KILL'}=sub{print "----".threads->self()->tid()." sync ".eval($port?$port:"").": send_stats2sock: recv KILL\n"; close $socket; threads->exit();};
	
	select($socket);
    $|=1;
    select(STDOUT);
    
	my $msj_2="2_".$opt{sid}."_".$opt{did};
	print   "----".threads->self()->tid()." sync : send_stats2sock: sending $msj_2 to gui (ask to handle my stats)\n";
	syswrite($socket,$msj_2);
	
    while(! $job_done){
        my $kb=eval($log{KB}{ADD}/1000);
        my $skipped=$log{F}{SKIP_ADD}+$log{F}{SKIP_ALT}+$log{F}{SKIP_DEL}+$log{F}{SKIP_REPL}+$log{F}{SKIP_U}+
        $log{D}{SKIP_ADD}+$log{D}{SKIP_ALT}+$log{D}{SKIP_DEL}+$log{D}{SKIP_U};
                                
        my $stats=$opt{sid}."_".$opt{did}."_".$log{F}{SCAN}."_".$log{F}{ADD}."_".$log{F}{DEL}."_".$log{F}{REPL}."_".$log{F}{ALT}."_".
                  $kb."_".$log{TIME}{ALL}."_".$skipped;    
        print "sync : send_stats2sock: sending $stats\n";
	    syswrite($socket,$stats);
	    sleep(2);
    }
    syswrite($socket,$opt{sid}."_".$opt{did}."_"."fin");
    close $socket;
    print   "----".threads->self()->tid()." send_stats2sock finishing..\n";
}
###########################################################################

# thread to wait for messages on the local port (given by gui or service)
sub wait_sock{
    #my ($port)=@_;  
    
    #####test
#    while(not $done){
#        print   $log{F}{SCAN}."\n";
#        sleep(5);
#    }
#    my $i;
#    while($q->dequeue()){
#        #$log{F}{SCAN}++;
#        $i++;
#        #print "$i \n";
#    }
    #####
    
    
    
    my $s = new IO::Socket::INET (
                                  LocalHost => '127.0.0.1',
                                  LocalPort => 0,
                                  Proto => 'tcp',
                                  Listen => 1,
                                  Reuse => 0
                               );
                                
    die "sync $port: Coudn't open socket (maybe the port is used)" unless $s;
    {
        lock($port);
        $port = $s->sockport();
    }
    
    if($opt{nogui}){
        print STDOUT << "EOF";
        
        ---------------------------------------------------------------------------------------
        !Warning!
        Option -nogui was set, gui.pl will not know that this runs.
        This is unsafe if another instance of sync.pl runs for the same source and destination.
        ---------------------------------------------------------------------------------------
EOF
    }else{
        # create portfile
        {   
            lock($portfile);
            $portfile=File::Spec->catfile($PORFILE_FOLDER, $opt{sid}.'.'.$opt{did}.'.'.$port.'.'."portfile"); 
            if( -f $portfile) {print "err: there is another process for this sid and did with this port. dying..\n"; die();}
            open (PFILE,'>',$portfile) or die "err: cannot create portfile: $!";    ##do nothing if port is unavailable..it is gui's fault
            print PFILE "bau";
            close PFILE;  
            print "sync $port: wait_sock: created portfile $portfile \n";  
        }
    }
    
    print  "\n----".threads->self()->tid()." sync $port:  waiting ..\n";

    my @cmd;
    while(my $cli=$s->accept()){
        $cli->recv(my $recv_data,1024);
            @cmd= split(/_/,$recv_data);
            #print "sync $port: recv ".$cli->peerport()." : ".@cmd."\n";
            if($cmd[0] eq "1"){
                    print "sync $port: recv 1\n";
                   # delete portfile
                   # sets done=1 >> sts2file thr stops >> sts file is in good state.
                   # kill thr that sends status messages to gui
                   # sync thr and joiner ...they die
                   
                   #if($thr_worker->is_running()){
                        #print "----".threads->self()->tid()." worker is running\n";
                        
                        sleep(1);
                        if($thr_worker->is_joinable()){
                            $thr_worker->join();
                            print   "----".threads->self()->tid()." sync $port: joined worker\n";
                        }
                        
                        if($thr_worker->is_running()){
                            $thr_worker->kill('KILL')->join();
                            print   "----".threads->self()->tid()." killed worker \n";
                        }
                        
                        
                   #}
                    
                    if($portfile) {
                        print   "----".threads->self()->tid()." sync $port: deleting portfile $portfile\n";
                        unlink($portfile) or print "sync $port: err: someone erased our portfile $portfile before us!! \n";
                        $portfile=undef;
                    }
                    
                    if($thr_stats2sock){
                        if($job_done){  
#                            {
#                                lock($done);
#                                $done=1;
#                            }
                            while(not $thr_stats2sock->is_joinable()){
                                print   "----".threads->self()->tid()." sync $port: waiting for thr_stats2sock to finish\n";
                                sleep(1);
                            }
                            $thr_stats2sock->join();
                            print   "----".threads->self()->tid()." sync $port: joined stats2sock\n";
                        }else{
                            $thr_stats2sock->kill('KILL')->join();
                            print   "----".threads->self()->tid()." sync $port: killed stats2sock\n";
                        }
                    }
                    # parent waits for this svariable .. even if the above conditions weren't met
                    {
                        lock($done);
                        $done=1;
                    }
                    
                    
                    
                    print   "----".threads->self()->tid()." sync $port: start_n_waitsock finishing..\n";
                    
#                    print "\n\nthr act: ";
#                    foreach(threads->list(threads::running)){
#                         print $_->tid()." ";
#                    }
#                    print "\n";
                    
                    threads->exit();
                    
#                   {##is it needed???
#                        lock($portfile);
#                        unlink($portfile) or print "sync $port: err: someone erased our portfile $portfile before us!! \n";
#                    }
#                    {
#                        lock($done);
#                        $done=1;
#                    } ##now wait just a sec so that sts thr finishes to write 
#                    sleep(1);
                    #$thr_stats2sock->kill('KILL')->detach();
                                    
            }elsif($cmd[0] eq "2"){  #gui asks for stats, start thr that sends stats to gui.,
                print "sync $port: recv 2 send stats\n"; 
                if(not $thr_stats2sock){
                    $thr_stats2sock=threads->new(\&send_stats2sock);
                }
            }elsif($cmd[0] eq "3"){ #gui does not want stats
                print "sync $port: recv 3 no more stats\n";
                if($thr_stats2sock){
                    $thr_stats2sock->kill('KILL')->join();
                    $thr_stats2sock=undef;
                }
            }elsif($cmd[0] eq "4"){
                print "sync $port: recv 4 , gui is on\n"; 
                &gui_is_on();
            }
    }
}
###########################################################################

# called if opt{gui} is set or if gui sends msj 4
sub gui_is_on{
    
    #get gui's port
    opendir( D, $PORFILE_FOLDER) or die ("----".threads->self()->tid()." err: cannot open portfile dir: $!");
    my @guis= grep /gui*/, readdir(D);
    if((scalar @guis)!=1){
        print   "----".threads->self()->tid()." sync : start_n_waitsock :  found ".eval(scalar @guis)." gui(s) in this directory...\n";
        return 0;
    }else{
        $guis[0]=~m/gui\_running\.([0-9]+)$/;
        $gui_port=$1;
        print  "gui port $gui_port \n" if($opt{v});
    }
    closedir(D);
    return 1; 
}
##################################

sub start_n_waitsock(){
    init;
    
    $SIG{'KILL'}=sub{
        print "----".threads->self()->tid()." start_n_waitsock dying..\n";
        threads->exit();
    };
    
    #init threads
    #$thr_stats2file=threads->new(\&drop_stats) or die("err create drop_sts thread: ".$!);
    $thr_worker= threads->new(\&sync_starter,$opt{s}, $opt{d}) or die("err create sync thread: ".$!);
    #$thr_sync_joiner=threads->new(\&wait_sync_fin) or die("err create wait_sync thread: ".$!);
    #thr to wait on our port. killed with no join, accept() blocks.
    
    #$thr_wait_socket=threads->new(\&wait_sock,$opt{port}) or die("err create wait_sock thread: ".$!);
    
    if($opt{gui}){  #gui is on, so we should start sending stats immediately
        if (not &gui_is_on()){
            if($thr_worker->is_running()){
                $thr_worker->kill('KILL')->join();
                print "----".threads->self()->tid()." killed worker \n";
            }
            
            {
                lock($done);
                $done=1;   
            }
            print   "----".threads->self()->tid()." sync : start_n_waitsock finishing..\n";
            threads->exit();
        }
        $thr_stats2sock=threads->new(\&send_stats2sock);
         #close STDERR;
         #close STDOUT;
         #open (STDOUT,">>",\$stderrs) or print "sync: main: could not redirect stdout $!\n";
         #open (STDERR,">>",\$stderrs) or print "sync: main: could not redirect stderr $!\n";
#        print "sync $port: gui on\n";
        
    }
    
    print   "worker: tid ".$thr_worker->tid()."\n" if ($opt{v});
    print   "start_n_wait: tid".threads->self()->tid()."\n" if ($opt{v});
#    print "\n\nthr act: ";
#    foreach(threads->list(threads::running)){
#        print $_->tid()."\n";
#    }
#    
    &wait_sock();
}

sub main {
    
    $thr_start_n_waitsock=threads->new(\&start_n_waitsock) or die("err create start_n_waitsock thread: ".$!);
    
    &drop_stats();
    $thr_start_n_waitsock->join();
    #&wait_sock($opt{port});
    print   "----".threads->self()->tid()." joined thr_start_n_waitsock; parent dying..\n";
    
    
    
    #print "main\n";
    #sleep(11111111);
    
    
    #print Dumper($log);

    #log
    
    #foreach (@job_logs) {
    #    $v_start =POSIX::strftime( "%H:%M:%S %d/%m/%y", localtime( $_->{STARTED} ) );
    #    $v_elapsed = POSIX::strftime( "%H:%M:%S", localtime( $_->{ELAPSED} ) );
    #    print LOGH pack( "A19 A9 A5 A10 A*",
    #        $v_start, $v_elapsed, $_->{TYPE}, $_->{ACTION}, $_->{PATH} )
    #      . "\n";
    #}
}

__END__



