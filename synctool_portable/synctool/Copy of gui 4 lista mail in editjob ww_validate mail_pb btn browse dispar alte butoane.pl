################################# param : -conf "path" (else default)
use strict;
use warnings;
use Getopt::Long;
use threads;
use threads::shared;
use XML::Simple;
use Data::Dumper;
use IO::Socket;
use Storable qw(lock_nstore lock_retrieve);
use POSIX;
use Carp;                  # prints stack trace
use Clone qw(clone);
use File::Spec::Win32;
################################# gui stuff
use Tk;
use Tk::Dialog;
use Tk::Entry;
use Tk::Label;
use Tk::Scrollbar;
use Tk::Text;
use Tk::Menu;
use Tk::Frame;
use Tk::DialogBox;
use Tk::Menubutton;
use Tk::Button;
use Tk::Radiobutton;
use Tk::Checkbutton;
use Tk::Toplevel;
use Tk::Optionmenu;
use Tk::NoteBook;
use Tk::LabEntry;
use Tk::LabFrame;
################################# vars

my $version = "3820934120";
my $lupdate = POSIX::strftime("%H:%M:%S %d/%m/%y",localtime((stat($0))[9]));
my $TOUCH_GUI_RUN=1;

my $listen_port:shared;

### Main Window vars
my $mw;
my $MW_listBox;
my $selected_job ; # job element selected in listbox

### Edit/Add job vars
#my @new_clients;
#my @new_exclude;
my $selected_client;
my $new_cli; # textvariable to hold new client to add
my $new_listBox_cli; 
my $selected_exclude;
my $new_exclude;
my $selected_exclude_re;
my $selected_email;
my $new_exclude_re;
my $new_email;
my $new_listBox_exclude; #gui
my $new_listBox_exclude_re; #gui
my $new_listBox_email;
my %stats;  #containg ViewWW components for each job that has a window
my $wwId=0;   # "view stats" window index 
my %info:shared; # {sid {did {thread, no(form sock msj)} } }
my %thr; # thr{sid}{did}
my %edit;   # {sid_wwId} , keep track of opened edit job windows
my $winAdd ; #only one edit/new ww at a time


print "###################################################################################\n";
################################################################################# READ PATHS FROM CONF
use constant{
    DEFAULT_CONF_PATH =>"D:\\_eclipse\\conf.xml"
};
my $xml_conf;
my $paths;
my $LOG_FOLDER;
my $PORFILE_FOLDER;
my $jobs_confFile;
my $sync_path;
my $BKP_FOLDER;
my $running_file;
my $touch_portfile_time;

GetOptions(
        "conf=s" => \$xml_conf,
        );
if (not $xml_conf) {$xml_conf= DEFAULT_CONF_PATH ;print "Using default configuration file: ".$xml_conf."\n"}
&loadPaths($xml_conf);

sub loadPaths{
    my $xml_conf_param = shift or undef;
    if(!$xml_conf_param){
        print "gui: loadPaths: Parameter xml_conf_param missing\n";
        return;
    }
    $paths=XMLin($xml_conf_param); # dies if conf not found
    
    my $running_folder=$paths->{running_folder};
    $running_folder =~ s!/$!!;
    $running_folder =~ s!\$!!;
    $LOG_FOLDER =$running_folder."\\".$paths->{logs_folder}."\\";
    $PORFILE_FOLDER = $running_folder."\\".$paths->{portfiles}."\\";
    
    $jobs_confFile = $running_folder."\\".$paths->{jobs_conf_filename};
    
    $sync_path=$running_folder."\\".$paths->{sync_path};
    $BKP_FOLDER = File::Spec::Win32->catdir($running_folder,$paths->{bkp_folder});
    
    if(not -d $PORFILE_FOLDER){
     mkdir $PORFILE_FOLDER or print "sync: err: creating $PORFILE_FOLDER\n";
    }
    $PORFILE_FOLDER =~s!/$!!;
    $PORFILE_FOLDER =~s!\$!!;
    $running_file=$PORFILE_FOLDER."\\gui_running";
    
    $touch_portfile_time=$paths->{touch_portfile_time};
    #die( "$running_folder \n$LOG_FOLDER \n$PORFILE_FOLDER\n$running_file \n$jobs_confFile \n$touch_portfile_time \n$sync_path \n$BKP_FOLDER\n");
}

################################################################################# READ JOBS CONF
my $conf;
my $xs; #will hold the xmlsimple obj
&readXmlJobs($jobs_confFile,1);
#my $conf=XMLin($jobs_confFile,forcearray=>[qw(client)]); #todo check if exists, print err parsing xml id any

&init(); #share this structure based on sid(s) and did(s) in %conf

my $thr_wait_sock=threads->new(\&wait_socket_msj)->detach();
my $thr_wait_kids=threads->new(\&wait_kids)->detach();
my $thr_touch_running_file;

$| = 1;

#foreach my $job ( keys %{$conf->{job}}){                
#    foreach(keys %{$conf->{job}{$job}{client}}){
#        print "dst: $conf->{job}{$job}{client}{$_}{addr} \n";  
#    }   
#}
#################################################################################

#needs $conf and $MW_listBox
sub MW_loadJobList{
    #my $MW_listBox =shift or ((print "no ww id to put the joblist\n" )&& return) ; ##?? mere
    my @job_list;
    my @job_ids =sort keys %{$conf->{job}};
    foreach(@job_ids) { push @job_list,$conf->{job}{$_}{title};}
    @job_list= sort{lc($a) cmp lc($b)} @job_list;
    $MW_listBox->delete('0', 'end');
    $MW_listBox->insert('end', @job_list);
}

############################################################################## # GUI elemets

sub unlink_running_file{
    if($listen_port){
        if(-f $running_file.".".$listen_port){
            unlink($running_file.".".$listen_port) or print "gui: err: could nou delete running file\n";
            print "gui: deleted running file\n";
        }else{
            print "gui: err: running file missing\n";
        }
   }
}

sub bbye{
    foreach my $sid_wwId (keys %stats){
        if($stats{$sid_wwId}{ww}){      
            print "ww $sid_wwId active\n";
            foreach (keys %{$stats{$sid_wwId}{cli}}){
                if($stats{$sid_wwId}{cli}{$_}{run}){
                    print "cli $_ running\n";
                    &send_msj3StopStats($stats{$sid_wwId}{cli}{$_}{port});   
                }   
            }
        }    
    }
#    $thr_wait_sock->kill('KILL');
#    print "gui: killed &wait_sock\n";
#    $thr_wait_kids->kill('KILL');
#    print "gui: killed &wait_kids\n";
    &unlink_running_file();
    threads->exit();
}

sub reloadJobsConf{
    # find last modified jobs_conf backup file and copy it into jobs conf file.
    # recreate $conf hash from file
    my $types = [
            ['Jobs Conf Backups',    '.jobs_bkp'],
            ['All files',    '*']
            ];
    my $fname=$mw->getOpenFile(-title => 'Load Backup:', -defaultextension => '.jobs_bkp', -initialdir => $BKP_FOLDER,
        -filetypes=>$types);
    return if(not $fname);
    &readXmlJobs($fname);
    &writeXmlJobs();
    &MW_loadJobList();
}

############### Create Main Window
$mw = MainWindow->new();

$mw->title ("SyncTool \@conti");
$mw->geometry('+40+350');
$mw->resizable(0,0);

############### handle EXIT
$mw->protocol('WM_DELETE_WINDOW',sub{ &bbye()} );
$SIG{'INT'}=sub{print "Cancelled.\n";&bbye()};  #switch to ww and back to make it work

############### File Menu
$mw->configure(
    -menu => my $menubar = $mw->Menu
    );
    
#my $file = $menubar->cascade(-label     => '~File',
#                             -tearoff   => 0, #?
#);
#
#$file->command(
#    -label       => "Close",
#    -accelerator => 'Ctrl-w',
#    -underline   => 0,
#    -command     => \&bbye,
#);

# Help Menu
my $help = $menubar->cascade(-label     => '~Help',
                             -tearoff   => 0,
);

$help->command(
   -label        => "About",
   -command      => sub{$mw-> messageBox(-title=>"About SyncTool",-message=>"SyncTool v ".$version.",\nmodified ".$lupdate."   ",-type=>'ok',-icon=>'info');},
);
####################################################################################### MAIN WINDOW TABS
my $nb = $mw->NoteBook( )->pack(-expand => 1, -fill => 'both');

my $tabJobs = $nb->add('Jobs', -label => 'Jobs');

my $tabService = $nb->add('Service', -label => 'Service');

my $tabConf = $nb->add('Configuration', -label => 'Configuration');

############################################# GLOBAL CONFIG TAB
 #my $frTabConf_Up   = $tabConf->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x', -padx => 1, -pady => 1.5);
 #my $frTabConf_Down   = $tabConf->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x', -padx => 1, -pady => 1.5);
    
 
# $frTabConf_Up->LabEntry(-label =>"Running Folder: ", -labelPack=>[-side => "left", -anchor => "w"], 
#                        -width=>30, -textvariable=>\$paths->{running_folder} )
#                        ->pack(-side => "top", -anchor => "nw");

my $frTabConf_head = $tabConf->Frame()->pack(-side => 'top',-padx => 10,-pady => 10);
my $frTabConf_Up = $tabConf->Frame()->pack(-side => 'top');
my $frTabConf_Left = $frTabConf_Up->Frame()->pack(-side => 'left',-padx => 10,-pady => 10);
my $frTabConf_Right = $frTabConf_Up->Frame()->pack(-side => 'right',-padx => 10,-pady => 10);
my $frTabConf_Bottom = $tabConf->Frame()->pack(-side => 'bottom',-padx => 10,-pady => 10);

$frTabConf_head->Label(-text =>"Configuration file located at: $xml_conf", -justify => 'left')->pack(-side => "top", -anchor => "nw");

$frTabConf_Left->Label(-text =>"Running Folder: ", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"Jobs Configuration Filename: ", -justify => 'left')->pack(-side => "top", -anchor => "nw");                       
$frTabConf_Left->Label(-text =>"Sync Script Filename: ", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"Porfiles Folder", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"Logs Folder", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"Backups Folder", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"Touch Portfiles Interval (sec):", -justify => 'left')->pack(-side => "top", -anchor => "nw");
$frTabConf_Left->Label(-text =>"SMTP Server:", -justify => 'left')->pack(-side => "top", -anchor => "nw");
  
my $confEntries={};   
#foreach (keys %$paths){     #cannot use : out of order (labels on the left do not correspond)                   
#     $confEntries->{$_}=$frTabConf_Right->Entry( -justify => 'left')->pack(-side => "top", -anchor => "nw");
#}

my @order=('running_folder','jobs_conf_filename','sync_path','portfiles','logs_folder','bkp_folder','touch_portfile_time','email_server');
foreach(@order) {
    $confEntries->{$_}=$frTabConf_Right->Entry( -justify => 'left')->pack(-side => "top", -anchor => "nw");
}

resetConfEntries();
$frTabConf_Bottom->Button(-text=>"Save",-command=>sub{&saveConf(1);})->pack(-side=>'left',-anchor=>'nw',-padx=>1);
$frTabConf_Bottom->Button(-text=>"Restore backup",-command=>sub{&restoreConf();})->pack(-side=>'left',-anchor=>'nw',-padx=>1);

sub resetConfEntries{
    foreach(keys %$paths){
        $confEntries->{$_}->delete(0,'end'); $confEntries->{$_}->insert(0,$paths->{$_});
    }
    
}
############################################# SERVICE TAB

############################################# JOBS TAB

my $t_frame = $tabJobs->Frame()->pack(-side => 'top');
#my $b_frame = $tabJobs->Frame()->pack(-side => 'bottom',-padx => 10,-pady => 10);
my $l_frame = $t_frame->Frame()->pack(-side => 'left');
    
$MW_listBox = $l_frame->Scrolled("Listbox", -selectmode => "single", -width => "50", -height => "13",  #?in ce il masoara
		  -scrollbars => 'osoe'); # optional south and optional east
&MW_loadJobList();

$MW_listBox->bind('<Button-1>', sub {
    $selected_job = $MW_listBox->get($MW_listBox->curselection());
    ## we have the name, we need to find the id corresponding to src
    foreach(keys %{$conf->{job}}){
        if($conf->{job}{$_}{title} eq $selected_job){
            $selected_job=$_;
            last;
        }
    }
});
$MW_listBox->pack(-side => 'top', -fill => 'both', -expand => 1);  #?

my $r_frame = $t_frame->Frame()->pack(-side => 'right',-padx => 10,-pady => 10);
    
my $btnAdd = $r_frame->Button(
     -text         => "Add", 
     -width        => 12,
     -command      => sub { &edit_job }
)->grid(-row=>0, -columnspan=>1, -sticky=>'nsew')
     ->pack(
     -side         => 'top',
     -anchor       => 'nw',     #north west position
);

my $btnDelete = $r_frame->Button(
     -text         => "Delete", 
     -width        => 12,
     -command      => sub { &delete_job($selected_job) if $selected_job;  }
)->grid(-row=>1, -columnspan=>1, -sticky=>'nsew')
     ->pack(
     -side         => 'top',
     -anchor       => 'nw', 
);

my $btnEdit = $r_frame->Button(
     -text         => "EditConf", 
     -width        => 12,
     -command      => sub { &edit_job($selected_job) if $selected_job; }
)->grid(-row=>2, -columnspan=>1, -sticky=>'nsew')
     ->pack(
     -side         => 'top',
     -anchor       => 'nw', 
);

my $btnView = $r_frame->Button(
     -text         => "ViewStats", 
     -width        => 12,
     -command      => sub { &view_job($selected_job,$wwId++) }
)->grid(-row=>3, -columnspan=>1, -sticky=>'nsew')
     ->pack(
     -side         => 'top',
     -anchor       => 'nw', 
);
#my $btn_close = $b_frame->Button(-text => "Close",-command => sub{bbye();})->pack(-side => 'left',-anchor=> 'nw', -padx => 3);
my $btn_reload = $r_frame->Button(-text => "Restore Config",-width=> 12,-command => sub{reloadJobsConf();})
    ->grid(-row=>5, -columnspan=>1, -sticky=>'nsew')
    ->pack(-side => 'bottom',-anchor=> 'nw');
##############################################################################

# Initiate Main Loop where the Loop.
MainLoop();
##############################################################################

# if it receives a parameter then it must edit the job selected, else we need to create a new one
sub edit_job{
    my $edit_sid = shift || undef;
    my $tmpJob={};
    #my %tmpJob;
    my $edit_flag=0;
    #do not allow multiple edit/new job windows...they share variables.
    if($winAdd ){
        return;
    }
    if(not $edit_sid){ 
        # NEW 
        #get next sid available and insert into conf hash
        my @tmp=keys %{$conf->{job}}; 
        @tmp=sort{$a <=> $b} @tmp;
        #print $tmp[-1]."\n";
        $edit_sid=$tmp[-1]+1;
        #print Dumper(@tmp)." ".$edit_sid."\n\n";
        $tmpJob->{master}='';
        $tmpJob->{title}='';
        $tmpJob->{start}='';
        $tmpJob->{ignore}="0";
        $tmpJob->{client}={};
        $tmpJob->{exclude}=[];
        $tmpJob->{exclude_re}=[];
        $tmpJob->{email}='';
    }else{
        # EDIT
        $tmpJob= clone($conf->{job}{$edit_sid}); #duplicate or same?    
        if( not ref $tmpJob->{client} eq "HASH"){
            $tmpJob->{client}={};
            print "clients null";
        }
        #print Dumper($tmpJob); 
        $edit_flag=1; 
    }
    
    $btnAdd->configure(-state=>'disabled');
    $btnEdit->configure(-state=>'disabled');
    
    #create ww
    $winAdd = $mw->Toplevel;
    $winAdd->geometry("+400+200");
    $winAdd->title("Edit Job");
    $winAdd->resizable(0,0);
    
    #################### Close
    $winAdd->protocol('WM_DELETE_WINDOW',sub{
        $winAdd ->destroy(); 
        $winAdd=undef;
        $btnAdd->configure(-state=>'normal');$btnEdit->configure(-state=>'normal');
        &writeXmlJobs();
        &MW_loadJobList();
    });
    
    my $t_frame = $winAdd->Frame()->pack(-side => 'top');
    my $l_frame = $t_frame->Frame()->pack(-side => 'left',-padx => 10,-pady => 10);
    my $r_frame = $t_frame->Frame()->pack(-side => 'right',-padx => 10,-pady => 10);
    
    my $b_frame = $winAdd->Frame()->pack(-side => 'bottom',-padx => 10,-pady => 10);
    
    my $l0_frame   = $l_frame->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x', -padx => 1, -pady => 1.5);
    my $l1_frame   = $l_frame->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x', -padx => 1, -pady => 1.5);
    
    $l0_frame->LabEntry(-label =>"Job Name", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>40, -textvariable=>\$tmpJob->{title} ) # or.. $edit_sid?\$edit_sid:undef
            ->pack(-side => "top", -anchor => "nw");
#    $l0_frame->Label(-text=>"Job Name:   $tmpJob->{title}")
#            ->pack(-side => "top", -anchor => "nw");
    $l0_frame->Label(-text => "___________________________________________________")
        ->pack(-side => 'top',-anchor=> 'nw', -padx => 1);
        
    $l1_frame->LabEntry(-label =>"Master share", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>30, -textvariable=>\$tmpJob->{master} ) 
            ->pack(-side => "left", -anchor => "nw", -padx => 1, -pady => 1);
    
    $l1_frame->Button(-text=>"Browse", -command => sub{
                 my $new=$winAdd->chooseDirectory(); 
                 if($new){
                     $tmpJob->{master}=$new;
                 }   
                },-height=>0.3)
            ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
            
    ################# ADD client , REMOVE and LISTBOX
    #$l_frame->grid($l_frame->Button(-text=>"+"),$l_frame->Button(-text=>"+"),-sticky=>"nw");
    my $lfClients =$l_frame->LabFrame(-label=>"Clients",-labelside => 'acrosstop')->grid(-row => 2,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $l2_frame   = $lfClients->Label->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    
    $l2_frame->LabEntry(-label =>"New Client ", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>25,-textvariable => \$new_cli,-background   => 'gray',)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
    
    $l2_frame->Button(-text=>"+", -command => sub{
            if($new_cli){
                #push @{$tmpJob->{client}},$new_cli if not $new_cli~~@{$tmpJob->{client}};
                
#                my $valid=1;
#                if(not -d $new_cli) {
#                    $winAdd->messageBox(-title=>"Error Invalid Path",-message=>"Client path '". $new_cli."' is invalid\n ",-type=>'ok',-icon=>'error');
#                    $valid=0;
#                }
#                if ($tmpJob->{master}~~$new_cli) {
#                    $winAdd->messageBox(-title=>"Error Invalid Client",-message=>"Client path equals master path.\n ",-type=>'ok',-icon=>'error');
#                    $valid=0;
#                }
#                if($valid) {   
                    my @indexes;
                    if(scalar %{$tmpJob->{client}}){
                        @indexes=sort keys %{$tmpJob->{client}};
                        my $ok=1;
                        foreach(values %{$tmpJob->{client}}){
                            if ($new_cli~~$_->{addr}) {$ok=0;}
                        }
                        $tmpJob->{client}{$indexes[-1]+1}{addr}=$new_cli if $ok;
                    }else{
                        #print "first cli\n";                                    
                        $tmpJob->{client}{"1"}{addr}=$new_cli;
                    }
#                }
                $new_cli='';
                &new_job_load_clients_listbox($tmpJob);
            }
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
    $l2_frame->Button(-text=>"-", -command => sub{
             if($selected_client){
                 foreach (keys %{$tmpJob->{client}}){
                    if( $tmpJob->{client}{$_}{addr} eq $selected_client){
                        delete($tmpJob->{client}{$_});
                        &new_job_load_clients_listbox($tmpJob);
                    }   
                 }
             }    
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
     $l2_frame->Button(-text=>"Browse", -command => sub{
                 $new_cli=$winAdd->chooseDirectory();   
                },-height=>0.3)
            ->pack(-side => 'left',-anchor=> 'nw', -padx => 2);
    
    my $l3_frame   = $lfClients->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    $new_listBox_cli = $l3_frame->Scrolled("Listbox", -selectmode => "single", -width => "45", -height => "8",  #?in ce il masoara
		  -scrollbars => 'osoe');
		  
    #$new_listBox->insert('end', @{$tmpJob->{client}});
    &new_job_load_clients_listbox($tmpJob);
    $new_listBox_cli->bind('<Button-1>', sub {
        $selected_client = $new_listBox_cli->get($new_listBox_cli->curselection());
    });
    $new_listBox_cli->pack(-padx=>5,-side => 'top',-anchor=> 'nw');  
    
    ################# email area
    my $lfMail =$l_frame->LabFrame(-label=>"Mail",-labelside => 'acrosstop')->grid(-row => 3,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
   
    my $l4_frame   = $lfMail->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $l5_frame   = $lfMail->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
   
    $l4_frame->LabEntry(-label =>"Mail To ", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>25,-textvariable => \$new_email,-background   => 'gray',)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
    
    $l4_frame->Button(-text=>"+", -command => sub{
            if($new_email){
                my $ok=1;
                my $valid=1;
                if($tmpJob->{email}){
                    my %h=map{$_=>1} @{$tmpJob->{email}};
                    $ok=0 if($h{$new_email});   
                }
                if($ok){  #validate email
                    $new_email=~m/^([a-zA-Z0-9_.]+)@([a-zA-Z0-9_-]+)(\.[a-zA-Z0-9]+)+$/;
                    if(not ($1||$2||$3) ){
                        $winAdd->messageBox(-title=>"Error Invalid Mail",-message=>"Email format is invalid. ",-type=>'ok',-icon=>'error');
                        $valid=0;
                    }
                }
                push @{$tmpJob->{email}},$new_email if( $ok and $valid);
                $new_email="";
                &new_job_load_email_listbox($tmpJob);
            }
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $l4_frame->Button(-text=>"-", -command => sub{
             if($selected_email){
                 my %h=map{$_=>1} @{$tmpJob->{email}};
                 delete $h{$selected_email};
                 @{$tmpJob->{email}}=keys %h;
                 &new_job_load_email_listbox($tmpJob);
             }    
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $new_listBox_email = $l5_frame->Scrolled("Listbox", -selectmode => "single", -width => "45", -height => "5",  #?in ce il masoara
		  -scrollbars => 'osoe');
    
    &new_job_load_email_listbox($tmpJob);
    
    $new_listBox_email->bind('<Button-1>', sub {
        $selected_email = $new_listBox_email->get($new_listBox_email->curselection());
    });
    $new_listBox_email->pack(-padx=>5,-side => 'top',-anchor=> 'nw');
    
    #################
    
    ################# RIGHT FRAME
    my $lfStart =$r_frame->LabFrame(-label=>"Startup",-labelside => 'acrosstop')->grid(-row => 3,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r0_frame   = $lfStart->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r1_frame   = $lfStart->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    
    my $lfExclude =$r_frame->LabFrame(-label=>"Exclude Filename",-labelside => 'acrosstop')->grid(-row => 3,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r2_frame   = $lfExclude->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r3_frame   = $lfExclude->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
   
    my $lfExcludeRe =$r_frame->LabFrame(-label=>"Exclude Filenames Containing",-labelside => 'acrosstop')->grid(-row => 3,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r4_frame   = $lfExcludeRe->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    my $r5_frame   = $lfExcludeRe->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-fill=>'x',-padx => 1, -pady => 1.5);
    
    $r0_frame->Checkbutton(-text=>"Ignore Job",-variable=>\$tmpJob->{ignore})
             ->pack(-side => "top", -anchor => "nw", -padx => 1);
    $r1_frame->LabEntry(-label =>"Start Time (hh:mm:ss) ", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>24, -textvariable=>\$tmpJob->{start} ) 
            ->pack(-side => "top", -anchor => "nw", -padx => 1);
            
    ########## exclude full name area
    
    $r2_frame->LabEntry(-label =>"New Filename", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>25,-textvariable => \$new_exclude,-background   => 'gray',)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
    
    $r2_frame->Button(-text=>"+", -command => sub{
            if($new_exclude){
                my $ok=1;
                if($tmpJob->{exclude}){
                    my %h=map{$_=>1} @{$tmpJob->{exclude}};
                    $ok=0 if($h{$new_exclude});   
                }
                push @{$tmpJob->{exclude}},$new_exclude if $ok;
                $new_exclude="";
                #if($edit_flag){
                    &new_job_load_exclude_listbox($tmpJob); 
                #}else{
                #    &new_job_load_exclude_listbox;
                #}
            }
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $r2_frame->Button(-text=>"-", -command => sub{
             if($selected_exclude){
                 my %h=map{$_=>1} @{$tmpJob->{exclude}};
                 delete $h{$selected_exclude};
                 @{$tmpJob->{exclude}}=keys %h;
                 &new_job_load_exclude_listbox($tmpJob); 
             }    
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $new_listBox_exclude = $r3_frame->Scrolled("Listbox", -selectmode => "single", -width => "45", -height => "6",  #?in ce il masoara
		  -scrollbars => 'osoe');
    #$new_listBox->insert('end', @{$tmpJob->{client}});
    
    &new_job_load_exclude_listbox($tmpJob); 
    
    $new_listBox_exclude->bind('<Button-1>', sub {
        $selected_exclude = $new_listBox_exclude->get($new_listBox_exclude->curselection());
    });
    $new_listBox_exclude->pack(-side => 'top',-anchor=> 'nw');
    
    ########## exclude regex area
    
    $r4_frame->LabEntry(-label =>"New Word ", -labelPack=>[-side => "left", -anchor => "w"], 
                        -width=>25,-textvariable => \$new_exclude_re,-background   => 'gray',)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
    
    $r4_frame->Button(-text=>"+", -command => sub{
            if($new_exclude_re){
                my $ok=1;
                if($tmpJob->{exclude_re}){
                    my %h=map{$_=>1} @{$tmpJob->{exclude_re}};
                    $ok=0 if($h{$new_exclude_re});   
                }
                push @{$tmpJob->{exclude_re}},$new_exclude_re if $ok;
                $new_exclude_re="";
                &new_job_load_exclude_re_listbox($tmpJob);
            }
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $r4_frame->Button(-text=>"-", -command => sub{
             if($selected_exclude_re){
                 my %h=map{$_=>1} @{$tmpJob->{exclude_re}};
                 delete $h{$selected_exclude_re};
                 @{$tmpJob->{exclude_re}}=keys %h;
                 &new_job_load_exclude_re_listbox($tmpJob);
             }    
        },-width=>2,-height=>0.3)
        ->pack(-side => 'left',-anchor=> 'nw', -padx => 1);
        
    $new_listBox_exclude_re = $r5_frame->Scrolled("Listbox", -selectmode => "single", -width => "45", -height => "6",  #?in ce il masoara
		  -scrollbars => 'osoe');
    #$new_listBox->insert('end', @{$tmpJob->{client}});
    &new_job_load_exclude_re_listbox($tmpJob);
    
    $new_listBox_exclude_re->bind('<Button-1>', sub {
        $selected_exclude_re = $new_listBox_exclude_re->get($new_listBox_exclude_re->curselection());
    });
    $new_listBox_exclude_re->pack(-side => 'top',-anchor=> 'nw');
    
    # SAVE 
    
    my $btn_close = $b_frame->Button(-text => "Close and Save to Configuration",
                                     -command => sub{
                                         my $err=0; # set if any err found
                                         my $err_mes;
                                         
                                         #vrfy start time 
                                         if (not $tmpJob->{start}) {
                                             $err_mes.="- Please specify a start time (eg. 12:59:00)\n" ;$err=1;
                                         }else{
                                             $tmpJob->{start}=~m/^([0-2][0-9]):([0-5][0-9]):([0-5][0-9])$/;
                                             #$winAdd-> messageBox(-message=>$1." ".$2." ".$3,-type=>'ok',-icon=>'error');
                                             if((not($1&&$2&&$3)) or $1>23 or $2>59 or $3>59){
                                                #$winAdd-> messageBox(-title=>"Error Time Format",-message=>"Please specify a valid start time\n eg. 12:59:00",-type=>'ok',-icon=>'error');
                                                #return;
                                                $err_mes.="- Please specify a valid start time (eg. 12:59:00).\n"; 
                                                $err=1;
                                             }
                                         }
                                         #vrfy duplicate or null job name
                                         if (not $tmpJob->{title}) {$err_mes.="- Please specify the job name\n"; $err=1;}
                                         foreach (keys %{$conf->{job}}){
                                            if(($conf->{job}{$_}->{title} eq $tmpJob->{title})&&(not $_==$edit_sid)){
                                                #$winAdd-> messageBox(-title=>"Error Duplicate Name",-message=>"Duplicate job name.",-type=>'ok',-icon=>'error');
                                                #return;
                                                $err_mes.="- Duplicate job name.\n"; 
                                                $err=1;
                                            }   
                                         }
                                         #vrfy master mandatory/valid path
                                         if(not $tmpJob->{master}) {$err_mes.="- Please specify a master share\n"; $err=1;}
                                         else{
                                             if(not -d $tmpJob->{master}) {$err_mes.="- Source path is invalid\n"; $err=1;}
                                         }
                                         #vrfy >1 client mandatory/valid paths
                                         if(not scalar %{$tmpJob->{client}}){
                                             $err_mes.="- Please specify at least one destination\n"; $err=1;
                                         }else{
                                             #print Dumper($tmpJob->{client});
                                             foreach (values %{$tmpJob->{client}}){
                                                 if(not -d $_->{addr}) {$err_mes.="- Client path '". $_->{addr}."' is invalid\n"; $err=1;}
                                             }
                                         }
                                         #vrfy any dest equals source
                                         foreach(values %{$tmpJob->{client}}){
                                             if ($tmpJob->{master}~~$_->{addr}) {
                                                 $err_mes.="- Client equals master\n"; $err=1;
                                             }
                                         }
                                         
                                         if($err){
                                             $winAdd-> messageBox(-title=>"Error Job Specifications",-message=>$err_mes,-type=>'ok',-icon=>'error');
                                             return;
                                         }
                                         $winAdd ->destroy(); 
                                         $winAdd=undef;
                                         $btnAdd->configure(-state=>'normal');$btnEdit->configure(-state=>'normal');
                                        
                                         $conf->{job}{$edit_sid}=$tmpJob;      
                                         &writeXmlJobs();
                                         &MW_loadJobList();
                                     })->pack(-side => 'left',-anchor=> 'nw', -padx => 3);
    my $btn_cancel = $b_frame->Button(-text => "Cancel",
                                     -command => sub{
                                         $winAdd ->destroy(); 
                                         $winAdd=undef;
                                         $btnAdd->configure(-state=>'normal');$btnEdit->configure(-state=>'normal');
                                     })->pack(-side => 'left',-anchor=> 'nw', -padx => 3);
}
###################################################

sub new_job_load_clients_listbox{
    #my $edit_sid = shift || '';
    #return if not $edit_sid;
    my $job= shift;
    
    $new_listBox_cli->delete('0', 'end');
    #my @adr=values %{$conf->{job}{$edit_sid}{client}};
    return if not ref $job->{client} eq "HASH";
    my @adr=values %{$job->{client}};   
    
    my @res;
    push @res,$_->{addr} foreach(@adr);
    @res=sort{lc($a) cmp lc($b)} @res;
    $new_listBox_cli->insert('end',@res);
}
####################################################

sub new_job_load_email_listbox{
    my $job= shift;
    $new_listBox_email->delete('0', 'end');
    $new_listBox_email->insert('end', sort{lc($a) cmp lc($b)} @{$job->{email}}) if ($job->{email});
}
####################################################

sub new_job_load_exclude_listbox{
    my $job= shift;
    $new_listBox_exclude->delete('0', 'end');
    $new_listBox_exclude->insert('end', sort{lc($a) cmp lc($b)} @{$job->{exclude}}) if ($job->{exclude});
}
####################################################

sub new_job_load_exclude_re_listbox{
    my $job= shift;
    $new_listBox_exclude_re->delete('0', 'end');
    $new_listBox_exclude_re->insert('end',sort{lc($a) cmp lc($b)} @{$job->{exclude_re}} ) if ($job->{exclude_re});
}
##############################################################################

sub delete_job{
    my $sid = shift || undef;
    return if not $sid;
    delete $conf->{job}{$sid};
    print Dumper($conf);
    &writeXmlJobs();
    &MW_loadJobList();    
}
##############################################################################

my $no_rows=0;
sub view_job{
    my $sid_wwId = shift || return;
    if($stats{$sid_wwId}{ww}){      #do not create a second window for the same job
        return;
    }
     
    #print "!!! stats! ".Dumper(%stats)."\n";
    
    #send message to all active processes in this job
    foreach(keys %{$stats{$sid_wwId}{cli}}){
        # active= their port was is defined in this sturucture
        if($stats{$sid_wwId}{cli}{$_}{port}){
            &send_msj2GetStats($sid_wwId,$stats{$sid_wwId}{cli}{$_}{port});
        }
    }
    
    
    my $winView = $mw->Toplevel;
    $winView->geometry("+470+200");
    $winView->title("View Job:  ".$conf->{job}{$sid_wwId}{title});
    $winView->resizable(0,0);
    
    $winView->protocol('WM_DELETE_WINDOW',sub{return;
#        $winView->destroy(); 
#        $stats{$sid_wwId}{ww}=undef;
#        #print "!! ok: ".Dumper($thr_ref);
#        foreach (keys %{$stats{$sid_wwId}{cli}}){
#            if($info{$sid_wwId}{$_}{run}){
#               &send_msj3StopStats($stats{$sid_wwId}{cli}{$_}{port});   
#            }   
#        }  
    });
    $stats{$sid_wwId}{ww}=\$winView;
    print "my ww id $sid_wwId \n";
    
    my $u_frame   = $winView->Frame->grid(-row => 0,-column => 0,-sticky => 'nw')->pack(-side => 'top',-padx => 10,-pady => 10,-fill=>'x');
    my $n_frame   = $winView->Frame->grid(-row => 1,-column => 0,-sticky => 'nw')->pack(-side => 'top',-padx => 10,-pady => 10,-fill=>'x');
    my $s_frame   = $winView->Frame->grid(-row => 2,-column => 0,-sticky => 'nw')->pack(-side => 'bottom',-padx => 10,-pady => 10,-fill=>'y');
    
    $u_frame->Label(-text=>"MASTER: ".$conf->{job}{$sid_wwId}{master}."    ")->grid(
    $u_frame->Button(-text=>"Start All", -command=>sub{})
    );
    
    ###
    my $lbl_CLIENT = $n_frame->Label(-text=> "CLIENT")->grid(
     my $lbl_STATE = $n_frame->Label(-text=> "STATE"),
     
     $n_frame->Label(-text=> "SCANNED"),
     $n_frame->Label(-text=> "ADD_F"),
     $n_frame->Label(-text=> "DEL_F"),
     $n_frame->Label(-text=> "REPL_F"),
     $n_frame->Label(-text=> "ALT_F"),
     $n_frame->Label(-text=> "ADD_KB"),
     $n_frame->Label(-text=> "TIME"),
     $n_frame->Label(-text=> "SKIP"),
     
     $n_frame->Label(-text=> "LASTRUN"),
     $n_frame->Label(-text=> "LAST_STS"),
#     $n_frame->Label(-text=> "-"),
#     $n_frame->Label(-text=> "-"),
#     $n_frame->Label(-text=> "-"),
     );


     foreach my $did ( keys %{$conf->{job}{$sid_wwId}{client}}){
         #@print "src: $conf->{job}{$job}{master} \n";
         my $cli=$conf->{job}{$sid_wwId}{client}{$did}{addr};
            
         #cli
         #print "btn param $sid_wwId ,$did \n";
         $n_frame->Label(-text=> $cli)->grid(   
         $stats{$sid_wwId}{cli}{$did}{lbl_RUN}= $n_frame->Label(-text=> "Stopped"),
         $stats{$sid_wwId}{cli}{$did}{lbl_SCANNED_F}= $n_frame->Label(-text=> "0"), # files scanned from source. todo
         $stats{$sid_wwId}{cli}{$did}{lbl_ADD_F}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_DEL_F}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_REPL_F}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_ALT_F}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_ADD_KB}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_TIME}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_SKIP}= $n_frame->Label(-text=> "0"),
         $stats{$sid_wwId}{cli}{$did}{lbl_LASTRUN}= $n_frame->Label(-text=> "-"),
         $stats{$sid_wwId}{cli}{$did}{lbl_LASTSTS}= $n_frame->Label(-text=> "-"),
         $stats{$sid_wwId}{cli}{$did}{btn_start}= $n_frame->Button(-text=>"Start", -command=>[\&start,$sid_wwId,$did]), 
         $stats{$sid_wwId}{cli}{$did}{btn_stop}= $n_frame->Button(-text=>"Stop", -command=>[\&stop,$sid_wwId,$did]),
         $stats{$sid_wwId}{cli}{$did}{btn_log}= $n_frame->Button(-text=>"Log", -command=>[\&view_last_log,$sid_wwId,$did]),
         # maybe the sync was interrupted unexpectedly .. so we have the last stats saved in sid_did_time (copied from the deleted portfile by sync.pl
         $stats{$sid_wwId}{cli}{$did}{btn_laststats}= $n_frame->Button(-text=>"LastStats", -command=>[\&view_last_stats,$sid_wwId,$did]), #todo create new ww with alist of stats from diff times.
         -sticky => "nsew", -padx => 3, -pady => 1
         );
         
#         $stats{$myWwId}{cli}{$_}{lbl_RUN}=$lbl_RUN;
#         $stats{$myWwId}{cli}{$_}{lbl_SCANNED_F}=$lbl_SCANNED_F;
#         $stats{$myWwId}{cli}{$_}{lbl_LASTRUN}=$lbl_LASTRUN;
#         $stats{$myWwId}{cli}{$_}{btn_start}=$btn_start;
#         $stats{$myWwId}{cli}{$_}{btn_stop}=$btn_stop;
#         $stats{$myWwId}{cli}{$_}{btn_log}=$btn_log;        
         
         #$job_labels{$job}{files}= $n_frame->Label(-text=> $files);
                
         $no_rows++;
         #print "dst: $did \n";
    }   
    #print Dumper(%stats);
    
    ###
    my $thr_ref=\%thr;
    my $btn_close = $s_frame->Button(-text => "Ok",-command => sub{
        $winView->destroy(); 
        $stats{$sid_wwId}{ww}=undef;
        #print "!! ok: ".Dumper($thr_ref);
        foreach (keys %{$stats{$sid_wwId}{cli}}){
            if($info{$sid_wwId}{$_}{run}){
               &send_msj3StopStats($stats{$sid_wwId}{cli}{$_}{port});   
            }   
        }   
    })->pack();
    #$lbl_LASTRUN->configure(-text=>"$no_rows");$winView->update();$no_rows++ 
    
    
    #my @my_ports;
    $winView->repeat(1000,sub{
        #&timer($sid_wwId)
        #####get running processes for this job
        
        #clear labels
        foreach(keys %{$stats{$sid_wwId}{cli}}){
            $stats{$sid_wwId}{cli}{$_}{file_exists}=0;
            if($info{$sid_wwId}{$_}{last_run}){
                $stats{$sid_wwId}{cli}{$_}{lbl_LASTRUN}->configure(-text=>$info{$sid_wwId}{$_}{last_run});
            }
            #print "!!\n".$info{$sid_wwId}{$_}{last_status}."\n";
            if($info{$sid_wwId}{$_}{last_status}){
                $stats{$sid_wwId}{cli}{$_}{lbl_LASTSTS}->configure(-text=>$info{$sid_wwId}{$_}{last_status});
            }
#            #$stats{$sid_wwId}{cli}{$_}{lbl_SCANNED_F}->configure(-text=>" "); # files scanned from source. todo
#            #$stats{$sid_wwId}{cli}{$_}{lbl_ADD_F}->configure(-text=>" ");
#            #$stats{$sid_wwId}{cli}{$_}{lbl_DEL_F}->configure(-text=>" ");
#            #$stats{$sid_wwId}{cli}{$_}{lbl_REPL_F}->configure(-text=>" ");
#            #$stats{$sid_wwId}{cli}{$_}{lbl_ALT_F}->configure(-text=>" ");
#            #$stats{$sid_wwId}{cli}{$_}{lbl_ADD_KB}->configure(-text=>" ");
#            #$stats{$sid_wwId}{cli}{$_}{lbl_TIME}->configure(-text=>" "); #todo
#            #$stats{$sid_wwId}{cli}{$_}{lbl_SKIP}->configure(-text=>" ");
        }
        opendir( D, $PORFILE_FOLDER) or die ("err: cannot open portfile dir: $!");
        my @portfiles= grep /.*\.portfile$/, readdir(D);
        #print "\n!!".Dumper(@portfiles)."\n\n";
        closedir(D);
#        foreach(keys %{$stats{$sid_wwId}{cli}}){
#            undef $stats{$sid_wwId}{cli}{$_}{port};
#        }
        #undef @my_ports; 
        foreach(@portfiles){
            /([0-9]+)\.([0-9]+)\.([0-9]+)\.portfile$/;
            if($1==$sid_wwId){ 
                print "!!found $3\n";
                $stats{$sid_wwId}{cli}{$2}{file_exists}=1;
                
                my $sec_since_last_modified=time-(stat($PORFILE_FOLDER.$_))[9];
                $stats{$sid_wwId}{cli}{$2}{port}=$3;
                #print "!!".Dumper(%info)." \n";
                if(not $info{$sid_wwId}{$2}{knows}){
                    # either started by someone else, either a remaining portfile from a failed process
                    if($sec_since_last_modified>$touch_portfile_time+2){
                        print "portfile $_ modified long ago\n";
                        $stats{$sid_wwId}{cli}{$2}{last_status}="Failed";
                        $stats{$sid_wwId}{cli}{$2}{port}=undef;
                        unlink($PORFILE_FOLDER.$_) or print "gui: winView->repeat: removing old portfile $_ \n";
                    }else{
                        print "gui: view_job: $stats{$sid_wwId}{cli}{$2}{port} does not know ...\n";
                        #if(($info{$sid_wwId}{$2}{run})&&(&send_msj2GetStats($sid_wwId,$stats{$sid_wwId}{cli}{$2}{port}))){
                        if((not $info{$sid_wwId}{$2}{stopped})&&(&send_msj2GetStats($sid_wwId,$stats{$sid_wwId}{cli}{$2}{port}))){
                            print "gui: setting info{ $sid_wwId }{ $2 }{knows} =1; ";
                            $info{$sid_wwId}{$2}{knows}="1";  
                        }  
                    }
                }else{
                    #maybe this portfile is from a recently stopped process
                    if($info{$sid_wwId}{$2}{stopped}){
                        print "!! $2 stopped by user\n";
                        $stats{$sid_wwId}{cli}{$2}{last_status}="Stopped";
                        next;   
                    }
                    $stats{$sid_wwId}{cli}{$2}{lbl_RUN}->configure(-text=>"Running");
                    
                    $stats{$sid_wwId}{cli}{$2}{btn_stop}->configure(-state=>'normal');
                    $stats{$sid_wwId}{cli}{$2}{btn_start}->configure(-state=>'disabled');
                    
                    $info{$sid_wwId}{$2}{run}=1;
                #if((time%10 eq 2) or (time%10 eq 7)){
#                    my $sts= lock_retrieve(PORFILE_FOLDER."\\".$_) or print "gui: $winView->repeat: retrieve failed\n";
#                    my $no=$sts->{F}{SCAN};
#                    #my $kb=eval($sts->{KB}{ADD}/1000000000%1000).".".eval($sts->{KB}{ADD}/1000000%1000).".".eval($sts->{KB}{ADD}/1000%1000);
#                    my $kb=eval($sts->{KB}{ADD}/1000);
#                    my $skipped=$sts->{F}{SKIP_ADD}+$sts->{F}{SKIP_ALT}+$sts->{F}{SKIP_DEL}+$sts->{F}{SKIP_REPL}+$sts->{F}{SKIP_U}+
#                                $sts->{D}{SKIP_ADD}+$sts->{D}{SKIP_ALT}+$sts->{D}{SKIP_DEL}+$sts->{D}{SKIP_U};
#                                
                    $stats{$sid_wwId}{cli}{$2}{lbl_SCANNED_F}->configure(-text=>$info{$sid_wwId}{$2}{SCANNED_F}); # files scanned from source. todo
                    $stats{$sid_wwId}{cli}{$2}{lbl_ADD_F}->configure(-text=>$info{$sid_wwId}{$2}{ADD_F});
                    $stats{$sid_wwId}{cli}{$2}{lbl_DEL_F}->configure(-text=>$info{$sid_wwId}{$2}{DEL_F});
                    $stats{$sid_wwId}{cli}{$2}{lbl_REPL_F}->configure(-text=>$info{$sid_wwId}{$2}{REPL_F});
                    $stats{$sid_wwId}{cli}{$2}{lbl_ALT_F}->configure(-text=>$info{$sid_wwId}{$2}{ALT_F});
                    $stats{$sid_wwId}{cli}{$2}{lbl_ADD_KB}->configure(-text=>$info{$sid_wwId}{$2}{ADD_KB});
                    $stats{$sid_wwId}{cli}{$2}{lbl_TIME}->configure(-text=>$info{$sid_wwId}{$2}{TIME}); #todo
                    $stats{$sid_wwId}{cli}{$2}{lbl_SKIP}->configure(-text=>$info{$sid_wwId}{$2}{SKIP});
                    #print Dumper($sts);
                #}
#                
                }
            }
        }
        
        foreach(keys %{$conf->{job}{$sid_wwId}{client}}){
            print "!$_ port ";
            if($stats{$sid_wwId}{cli}{$_}{port}){
                print $stats{$sid_wwId}{cli}{$_}{port};
            }
            print " , run ";
            if($info{$sid_wwId}{$_}{run}){
                print  $info{$sid_wwId}{$_}{run};  
            }
            print " \n";
#            if((not $stats{$sid_wwId}{cli}{$_}{port})&&(not $info{$sid_wwId}{$_}{run})){
#            if(not $info{$sid_wwId}{$_}{run}){
            if(not $stats{$sid_wwId}{cli}{$_}{file_exists}){ 
                #print "destination not running: $_ \n";
                
                $stats{$sid_wwId}{cli}{$_}{lbl_RUN}->configure(-text=>"Stopped");
                #$info{$sid_wwId}{$_}{run}=0;
                $info{$sid_wwId}{$_}{knows}=0;
                $stats{$sid_wwId}{cli}{$_}{port}=undef;
                {
                     lock(%info);
                     $info{$sid_wwId}{$_}{stopped}=0;
                }
                $stats{$sid_wwId}{cli}{$_}{btn_stop}->configure(-state=>'disabled');
                $stats{$sid_wwId}{cli}{$_}{btn_start}->configure(-state=>'normal');
                #$stats{$sid_wwId}{cli}{$_}{port}=undef;
                my $lastfile=&get_last_modified_file($sid_wwId,$_);
                if($lastfile){
                    my $lasttime=(stat($lastfile))[9];
                    $info{$sid_wwId}{$_}{last_run}=POSIX::strftime("%H:%M:%S %d/%m/%y",localtime($lasttime));
                    #print "last file $lastfile \n";
                }
            }
        }
        #print "!! all thr ".threads->list(threads::all).Dumper(%thr)."\n";
        ############################
        $winView->update();
        #print "updated ww $sid_wwId \n";
        #print "my ports are: ",Dumper(@my_ports);
    });
    
    ##send message2[sid_wwId] (ask stats) to all my ports
    
#    foreach (@my_ports){
#        &send_msj2GetStats($sid_wwId,$_); 
#        print "gui: sent msj2 to $_ \n";
#    }
}

#sub close_ww{
#    my ($sid_wwId,$thr,$winView)=@_;
#    $winView->destroy(); 
#    $stats{$sid_wwId}{ww}=undef;
#    foreach (keys %{$thr->{$sid_wwId}}){
#        if($thr{$sid_wwId}{$_}){
#               &send_msj3StopStats($sid_wwId,$stats{$sid_wwId}{cli}{$_}{port});   
#        }   
#    }   
#}
#####################################

# starts a new sync job # params sid,did
sub start{
    my ($sid_wwId,$did)=@_;
    #print "sid and did: $sid_wwId $did \n";

    #start process
    my @cmd1=("perl",$sync_path,"--s",$conf->{job}{$sid_wwId}{master},"--d",$conf->{job}{$sid_wwId}{client}{$did}{addr},"-sid",$sid_wwId,"-did",$did,"--gui");   #"2>nul"
    if($conf->{job}{$sid_wwId}{exclude}){
        push @cmd1,"-excl";
        foreach( @{$conf->{job}{$sid_wwId}{exclude}}){
            push @cmd1,$_.",";
        }
    }
    if($conf->{job}{$sid_wwId}{exclude_re}){
        push @cmd1,"-exclre";
        foreach( @{$conf->{job}{$sid_wwId}{exclude_re}}){
            push @cmd1,$_.",";
        }
    }
    print "\ngui calling: \n@cmd1 \n";
#    my $pid=fork();
#    if(not defined $pid){
#        print("err fork : $sid_wwId to $did \n");
#    }elsif($pid==0){
#        system(@cmd1);
#        exit;
#    }
    system 1,@cmd1;
    print "started $sid_wwId to $did \n";
    #"knows" means that this process knows about our presence (in this case it was started by us)
    {
        lock(%info);
        $info{$sid_wwId}{$did}{knows}="1";
        #$info{$sid_wwId}{$did}{run}="1";   #if set ,if sync dies because there are to mane gui running, it will remain set
    }    
    #print "!!\n".Dumper(%info)."\n";
    #$lock++;

    
    #ask for stats  
    #&send_msj2GetStats($sid_wwId,$nextport);    #???make thr
}
#####################################

#params: windowId, port where to send
# ... expected recv msj2 (wwid,port,stats) 
sub send_msj2GetStats{
    my ($sid_wwId,$port)=@_;
    print "gui: send_msj2GetStats ".$sid_wwId." ".$port."\n";
    my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $port,
                                  Proto => 'tcp',
                               ) ;               
	if(not $socket){
	    print "gui: Couldn't connect to $port to send msj2\n";   
	    return 0;
	}
	
    select($socket);
	$|=1;
	select(STDOUT);
	my $msj_2="2";
	syswrite($socket,$msj_2);
	close $socket;
	print "gui: sent $msj_2 to $port \n";
	#sleep(0.5);
	return 1;
}
#####################################

#params: windowId, port where to send
sub send_msj3StopStats{
    my ($port)=@_;
    print "gui: send_msj3StopStats to $port \n";
    my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $port,
                                  Proto => 'tcp',
                               )   ;             
    if(not $socket){
        print "gui: Couldn't connect to $port to send msj3\n";   
        return;
    }
    select($socket);
    $|=1;
    select(STDOUT);
    my $msj_3="3";
    syswrite($socket,$msj_3);
    close $socket;
    print "gui: sent $msj_3 to $port \n";
}
#####################################

# send this message to all processes that are already there when we start
sub send_msj4GuiOn{
    my ($port)=@_;
    print "gui: send_msj4GuiOn to $port \n";
    my $socket = new IO::Socket::INET (
                                  PeerAddr  => '127.0.0.1',
                                  PeerPort  =>  $port,
                                  Proto => 'tcp',
                               )                
    or print "gui: Couldn't connect to $port to send msj3\n";   
    select($socket);
    $|=1;
    select(STDOUT);
    my $msj_4="4";
    syswrite($socket,$msj_4);
    close $socket;
    print "gui: sent $msj_4 to $port \n";
}
#####################################
sub stop{
    my ($sid_wwId,$did)=@_;
    print "gui: sid and did: $sid_wwId $did \n";
    my $port=$stats{$sid_wwId}{cli}{$did}{port};
    if(!$port){
        return;   
    }
    print "gui: sending msj 1 stop on port $port \n";
    # send msj 1 
    #print "!!!".threads->list(threads::all)."\n";
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
	
	{
        lock(%info);
        $info{$sid_wwId}{$did}{run}=0;
        #$info{$sid_wwId}{$did}{knows}=0;   #..
        $info{$sid_wwId}{$did}{stopped}=1;
    }
    #$stats{$sid_wwId}{cli}{$did}{port}=undef; #useless , it will be set by repeat until portfile is deleted by sync
	
	# we also need to clear the thread ,sh..
	#print "!!!".threads->list(threads::all)."\n";
	#my $thr=&get_thr_from_hash($sid_wwId,$did);
	#print "!!my thr ".$thr."\n";
	
	#sleep(0.5);
}
#####################################

# only those that have been saved into a files such as "1to2_(date).stats"
sub view_last_stats{
    my ($s,$d)=@_;
    print "gui: view_last_stats: sid and did: $s $d \n";

    opendir( D, $LOG_FOLDER) or die ("gui: view_last_stats: err: cannot open portfile dir: $!");
    my $laststats;
    my @statsfiles= grep /^($s)_($d).*\.stats/, readdir(D);
    #print Dumper(@statsfiles);
    my @sorted=sort{-M $LOG_FOLDER.$a <=> -M $LOG_FOLDER.$b} @statsfiles;
    closedir(D);
    if(scalar @sorted){
        $laststats=$sorted[0];
        #print "gui: view_last_stats: file with last mtime is $laststats, mtime ".POSIX::strftime( "%H:%M:%S %d/%m/%y", gmtime( -M PORFILE_FOLDER.$laststats ) )." \n";    
        my @cmd=("start","notepad.exe",$LOG_FOLDER.$laststats);
        system 1,@cmd;
        print "started notepad \n";
    }
}
#####################################

sub view_last_log{
    my ($s,$d)=@_;
    print "gui: view_last_log: sid and did: $s $d \n";

#    opendir( D, PORFILE_FOLDER) or die ("gui: view_last_log: err: cannot open portfile dir: $!");
#    my $lastlog;
#    my @logfiles= grep /^($s)_($d).*\.log/, readdir(D);
#    my @sorted=sort{-M PORFILE_FOLDER.$a <=> -M PORFILE_FOLDER.$b} @logfiles;
#    closedir(D);
    my $lastlog=&get_last_modified_file($s,$d);
    if($lastlog){
        my @cmd=("start","notepad.exe",$lastlog);
        system 1,@cmd;
        print "started notepad \n";
    }
}
#####################################

sub get_last_modified_file{
    my ($s,$d)=@_;
    opendir( D, $LOG_FOLDER) or die ("gui: view_last_log: err: cannot open portfile dir: $!");
    my $lastlog;
    my @logfiles= grep /^($s)_($d).*\.log/, readdir(D);
    my @sorted=sort{-M $LOG_FOLDER.$a <=> -M $LOG_FOLDER.$b} @logfiles;
    closedir(D);
    if(scalar @sorted){
        return $LOG_FOLDER.$sorted[0];
    }else{
        return undef;   
    }
}
##############################################################################

# gets the statistics from socket for just one sync 
# modifies %info{wwId_sid}{did}{sts}
sub handle_one_proc{
    my ($cli)=@_;
    print "gui $listen_port: handle_one_proc: cli $cli \n";
    
    #my ($remote_port,$my_port)=@_;
    #print "gui $listen_port: handle_one_proc: remote port $remote_port, local $my_port \n";
    
    $SIG{'KILL'}=sub{
        #send to sync port msj3 no more stats
        # this is called when we close the window for our job
    };
    # bind to a port 
    # todo create a loop to try to bind to another if used.
#    my $s = new IO::Socket::INET (
#                                  LocalHost => '127.0.0.1',
#                                  LocalPort => $my_port, 
#                                  Proto => 'tcp',
#                                  Listen => 1,
#                                  Reuse => 1
#                               );
#                                
#    die "gui $listen_port: handle_one_proc: Coudn't open $my_port" unless $s;
      
    # send to sync sock our port to which he should connect and send sts
#    my $temp_s = new IO::Socket::INET (
#                                  PeerAddr  => '127.0.0.1',
#                                  PeerPort  =>  $remote_port,
#                                  Proto => 'tcp',
#                               )
#    or print "gui: handle_one_proc: Couldn't connect to $remote_port to send my port to ask it to connect back \n";  
#    select($temp_s);
#    $|=1;
#    select(STDOUT);
#    my $msj="4_$my_port";
#    syswrite($temp_s,$msj);
#    close $temp_s;

    # wait for sts ,loop
    
#    my $cli=$s->accept();


    while($cli->recv(my $recv_data,1024)){
        if(not $recv_data){
            print "gui: handle_one_proc: socket closed\n";
            close($cli);
            threads->exit();
        }
        my @cmd=split(/_/,$recv_data);
        if($cmd[2] eq "fin"){
            print "gui: handle_one_proc: recv @cmd ,close socket\n";
            close($cli);
            {
                lock(%info);
                $info{$cmd[0]}{$cmd[1]}{last_status}="Success";
                $info{$cmd[0]}{$cmd[1]}{run}="0";
                $info{$cmd[0]}{$cmd[1]}{knows}="0";
            }
            #print "!!\n".Dumper(%info)."\n";
            threads->exit();   
        }
        
        print "gui: handle_one_proc: recv @cmd \n";
        {
            lock(%info);
            $info{$cmd[0]}{$cmd[1]}{SCANNED_F}=$cmd[2];
            $info{$cmd[0]}{$cmd[1]}{ADD_F}=$cmd[3];
            $info{$cmd[0]}{$cmd[1]}{DEL_F}=$cmd[4];
            $info{$cmd[0]}{$cmd[1]}{REPL_F}=$cmd[5];
            $info{$cmd[0]}{$cmd[1]}{ALT_F}=$cmd[6];
            $info{$cmd[0]}{$cmd[1]}{ADD_KB}=$cmd[7];
            $info{$cmd[0]}{$cmd[1]}{TIME}=$cmd[8];
            $info{$cmd[0]}{$cmd[1]}{SKIP}=$cmd[9];
            $info{$cmd[0]}{$cmd[1]}{knows}=1;
            #$info{$cmd[0]}{$cmd[1]}{run}=1;    #if gui recv data after stop btn(run=0) this will remain 1 for an enden process
            #print " info{$cmd[0] }{$cmd[1] }{scan}=$cmd[2] ;\n";
        }
    }
}

#sub get_thr_from_hash{
#    my ($s,$d)=@_;
#    return $thr{$s}{$d};   
#}
##############################################################################

sub wait_socket_msj{
    ##msj1: running=0 no need, we check for portfiles on filesystem
    #msj2: alter %info{sid}{did}{SCANF} 
    #{
        #lock($listen_port);
        
    $SIG{'KILL'}=sub{
        print "gui: wait_socket_msj: thr dying..\n";
        threads->exit();  
    };
    my $s = new IO::Socket::INET (
                                  LocalHost => '127.0.0.1',
                                  LocalPort => 0,
                                  Proto => 'tcp',
                                  Listen => 200,
                                  Reuse => 0
                               );
                                
    die "gui $listen_port: Coudn't open $listen_port" unless $s;
    
    {
        lock($listen_port);
        $listen_port=$s->sockport();    
    }
    opendir( D, $PORFILE_FOLDER) or die ("err: cannot open portfile dir: $!");
    my @guis= grep /gui_running.*$/, readdir(D);
    closedir(D);
        
    if (scalar @guis) {
        #2 posibilities: 1.last gui died unexpectedly, 2.another instance of gui is running
        
        my $sec_since_last_modified;
        foreach(@guis){
            print "!!: ".$PORFILE_FOLDER.$_."\n";
            $sec_since_last_modified=time-(stat($PORFILE_FOLDER.$_))[9];
            if($sec_since_last_modified>$TOUCH_GUI_RUN+1){
                print "this is dead: $_\n";
                unlink($PORFILE_FOLDER.$_) or print "gui: err: could not unlink $_ \n";
            }else{
                print "There is another instance of gui running! Quitting..\n";
                exit(0);
            }
        }
    }
    $thr_touch_running_file=threads->new(\&touch_running_file)->detach();  #only touches if this file is already there
    open (F,'>',$running_file.".".$listen_port) or die "err: cannot create RUNNING_FILE: $!";   
    print F "bau";
    close F;  
    print "created RUNNING_FILE \n";
    
    #signal our presence to all processes that are already started so that they will know our port before we ask stats from them
    opendir( D, $PORFILE_FOLDER) or die ("gui: init: err: cannot open portfile dir: $!");
    my @portfiles= grep /.*\.portfile$/, readdir(D);
    closedir(D);
    foreach(@portfiles){
        my $sec_since_last_modified=time-(stat($PORFILE_FOLDER.$_))[9];
        /([0-9]+)\.([0-9]+)\.([0-9]+)\.portfile$/;
        
        if($sec_since_last_modified<=$touch_portfile_time){
            &send_msj4GuiOn($3);
        }
    }
    
    print "\ngui $listen_port: Waiting .. \n";

    my @cmd;
    while(my $cli=$s->accept()){
        $cli->recv(my $recv_data,1024); 
            print "gui $listen_port: accepted: ".$cli->peerport()." : ".$recv_data."\n";
            @cmd= split(/_/,$recv_data);
            if($cmd[0] eq 2){
                print "gui $listen_port: recv 2, sid $cmd[1] did $cmd[2] \n";
                $thr{$cmd[1]}{$cmd[2]}=threads->new(\&handle_one_proc,$cli);
                #print Dumper(%thr)."\n";
            }
    #}
    
    } 
}
##############################################################################

sub wait_kids{
    $SIG{'KILL'}=sub{
        print "gui: wait_kids: thr dying..\n";
        threads->exit();  
    };
    while(1){
        #print "gui: thr wait_kids: joinable: ".Dumper(threads->list(threads::joinable))."\n";
        foreach(threads->list(threads::joinable)){
            $_->join();
        }
        #print "gui: thr wait_kids: joinable: ".Dumper(threads->list(threads::joinable))."\n";
        sleep(2);
    }
}

##############################################################################

sub touch_running_file{
    $SIG{'KILL'}=sub{
        print "gui: touch_running_file: thr dying..\n";
        threads->exit();  
    };
    while(1){
        #if($listen_port){
            if(-f $running_file.".".$listen_port){
                open (F,'>',$running_file.".".$listen_port) or die "err: cannot touch RUNNING_FILE: $!";   
                print F "bau";
                close F; 
                #print "thr :touched\n"; 
            }   
        #}
        sleep($TOUCH_GUI_RUN);
        
    }
}

##############################################################################

sub init{

    #share the %info because this will be modified by each thread that receives stats from a process
    foreach my $sid (keys %{$conf->{job}}){
        $info{$sid}=&share({});
        print $sid."\n";
        if(not ref $conf->{job}{$sid}{client} eq "HASH") {next;}
        #print "\n".Dumper($conf->{job}{$sid}{client})."\n";
        foreach my $did( keys %{$conf->{job}{$sid}{client}} ){
            #print "gui: sharing info{$sid }{$did }\n";
            $info{$sid}{$did}=&share({});
            #share $info{$sid}{$did}{thr};
            #share $info{$sid}{$did}{sts};
            share $info{$sid}{$did}{scan};
        }
    }
    
    
}
############################################################################## XML STUFF
sub validateConf{
    #duplicate job names
    my %names;
    $names{$conf->{job}{$_}{title}}=0 foreach keys %{$conf->{job}};
    $names{$conf->{job}{$_}{title}}++ foreach keys %{$conf->{job}};
    #print Dumper(%names);
    foreach (keys %names){
        if($names{$_}>1){
            die("Invalid jobs config: Duplicate  job name\n");
        }
    }
    
    #duplicate clients for job
    my %clients;
    foreach my $sid (keys %{$conf->{job}}){
        #print "$sid\n";
        die "Invalid jobs config: Job ".$sid." must contain a master\n" if(not $conf->{job}{$sid}{master});
        undef %clients;
        
        #not at least 1 client 
        die "Invalid jobs config: Job ".$sid." must contain at least one client\n" if(not (ref $conf->{job}{$sid}{client} eq "HASH"));
        $clients{$conf->{job}{$sid}{client}{$_}{addr}}=0 foreach keys %{$conf->{job}{$sid}{client}};
        $clients{$conf->{job}{$sid}{client}{$_}{addr}}++ foreach keys %{$conf->{job}{$sid}{client}};
        #print Dumper(%clients);
        foreach (keys %clients){
            if($clients{$_}>1){
                die("Invalid jobs config: Duplicate client for job with id ".$sid."\n");
            }
        }
    }
}

sub writeXmlJobs{
    #my $out= $xs->XMLout( $conf,keeproot => 1,XMLDecl => "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>" ) ;
    my $out= $xs->XMLout( $conf,KeyAttr=>[qw/id/],XMLDecl => "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>" ) ;
    open (my $conffile,'>',$jobs_confFile) or die($!);
    print $conffile $out;
    close ($conffile);   
}

sub readXmlJobs{
    #first backup the last $jobs_confFile
    my ($jobsConf,$bkp_flag)= @_;
    return if not $jobsConf;
    
    if($bkp_flag){
        my $bkp_ext=POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".jobs_bkp";
        print "Backing up jobs conf\n";
        #die('copy ', "\"$jobsConf\" ", " \"".$BKP_FOLDER."\\".$paths->{jobs_conf_filename}.$bkp_ext."\"");
        my @cmd=("copy",$jobsConf,$BKP_FOLDER."\\".$paths->{jobs_conf_filename}.$bkp_ext);
        if ( system(@cmd) ) {
            print "gui: readXmlJobs: err backing up $jobsConf \n ";
        }
    }
    # The fastest existing backend for XML::Simple.
    local $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    $xs = XML::Simple->new(
       NoAttr         => 1,
       KeepRoot       => 0,
       NormaliseSpace => 1,
    );
    
    my $document = do {
        local $/ = undef;
        open my $fh, "<",$jobsConf
            or die "could not open : $!";
        <$fh>;
    };
    $conf = $xs->XMLin($document,KeyAttr=>[qw/id/],forcearray=>[qw(client exclude exclude_re email)]); #,KeyAttr=>[], keeproot => 1);
    print Dumper($conf);
    &validateConf();
}

sub saveConf{
    # backup(if given a parameter) then write
    my $bkp_flag=shift or undef;
    if($bkp_flag){
        my $bkp_ext=POSIX::strftime("_%H.%M.%S_%d.%m.%y",localtime).".conf_bkp";
        print "Backing up global conf\n";
        $xml_conf=~m/[\/\\]([a-z0-9._]*)$/;
        my $conf_filename=$1;
        if(!$conf_filename){
           print "Cannot determine configuration file name from path: $xml_conf\n";
           return;
        }
        my @cmd=("copy",File::Spec->catfile($xml_conf),File::Spec->catfile($BKP_FOLDER,$conf_filename.$bkp_ext));
        print Dumper(@cmd)."\n";
        if ( system(@cmd) ) {
            print "gui: saveConf: err backing up $xml_conf :$! \n ";
        }
    }
    open(my $h,'>',$xml_conf) or print "Error opening $xml_conf: $!\n";
    print $h $xs->XMLout($paths);
}

sub restoreConf{
    #copies into conf file and reloads paths
     my $types = [
            ['Global Conf Backups',    '.conf_bkp'],
            ['All files',    '*']
            ];
    my $fname=$mw->getOpenFile(-title => 'Load Backup:', -defaultextension => '.conf_bkp', -initialdir => $BKP_FOLDER,
        -filetypes=>$types);
    return if(not $fname);
    &loadPaths($fname);
    $tabConf->update();
    &saveConf();
    &resetConfEntries;
}