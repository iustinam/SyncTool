use strict;
use warnings;
use Getopt::Long;
use XML::Simple;
use Data::Dumper;
use POSIX;
use File::Spec;
##############################################################################################################

my $xml_conf;
my $paths;
my $PORFILE_FOLDER;
my $jobs_confFile;
my $sync_path;
my $linux_perl_path;
my $smtp_server;
my $linux_scheduler_log_path;

my %conf_invalid;
my $conf;

use constant{
    DEFAULT_CONF_PATH =>"/home/uidu3198/SyncTool1/SyncTool/synctool_portable/synctool/conf.xml",#"/home/bkt/synctool/conf.xml",
    DEFAULT_SCHEDULER_LOG_PATH=>"/home/bkt/scheduler.log",
};
##############################################################################################################

sub loadPaths{
    my $xml_conf_param = shift or undef;
    if(!$xml_conf_param){
        print "gui: loadPaths: Parameter xml_conf_param missing\n";
        return;
    }
    $paths=XMLin($xml_conf_param); # dies if conf not found
    
    my $running_folder=$paths->{running_folder};
    if((not $running_folder)||(not -d $running_folder)){
       die "gui: loadPaths: no/invalid running_folder\n";
    }
    
    
    
    if($paths->{portfiles}){
        $PORFILE_FOLDER =File::Spec->catdir($running_folder,$paths->{portfiles});
        if(not -d $PORFILE_FOLDER){
            mkdir $PORFILE_FOLDER or print "gui: err: creating $PORFILE_FOLDER\n";
        }
    }else{
        $conf_invalid{portfiles}="* Mandatory. Using 'run'";
        $PORFILE_FOLDER =File::Spec->catdir($running_folder,"run");
        mkdir $PORFILE_FOLDER or print "gui: err: creating $PORFILE_FOLDER\n";
    }
    
    if($paths->{jobs_conf_filename}){
        $jobs_confFile = File::Spec->catfile($running_folder,$paths->{jobs_conf_filename});
        if(not -f $jobs_confFile){
            $conf_invalid{jobs_conf_filename}="* Invalid.";
        }
    }else{
        $conf_invalid{jobs_conf_filename}="* Mandatory.";
    }
    
    if($paths->{sync_path}){
        $sync_path=File::Spec->catfile($running_folder,$paths->{sync_path});
        if(not -f $sync_path){
            $conf_invalid{sync_path}="* Invalid.";
        }
    }else{
        $conf_invalid{sync_path}="* Mandatory.";
    } 
    
    if($paths->{linux_scheduler_log_path}){
        $linux_scheduler_log_path=File::Spec->catfile($running_folder,$paths->{linux_scheduler_log_path});
    }else{
        $linux_scheduler_log_path=DEFAULT_SCHEDULER_LOG_PATH;
        $conf_invalid{linux_scheduler_log_path}="* default: scheduler.log";
    }
    
    if($paths->{linux_perl_path}){
        $linux_perl_path=File::Spec->catfile($paths->{linux_perl_path});
        if(not -f $linux_perl_path){
            $conf_invalid{linux_perl_path}="* Invalid. Using 'perl'.";
            $linux_perl_path="perl";
        }
    }else{
        $conf_invalid{linux_perl_path}=" Using 'perl'";
        $linux_perl_path="perl";
    }
    
    $smtp_server=$paths->{email_server} or $conf_invalid{email_server}="* No email will be sent." ;
    
    #die( "$running_folder \n$LOG_FOLDER \n$PORFILE_FOLDER\n$running_file \n$jobs_confFile \n$touch_portfile_time \n$sync_path \n$BKP_FOLDER\n");
}

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

sub readXmlJobs{
    #first backup the last $jobs_confFile
    my ($jobsConf)= @_;
    return if not $jobsConf;
    
    # The fastest existing backend for XML::Simple.
    local $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    my $xs = XML::Simple->new(
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

sub main{
    GetOptions(
        "conf=s" => \$xml_conf,
        );
    if (not $xml_conf) {$xml_conf= DEFAULT_CONF_PATH ;print "Using default configuration file: ".$xml_conf."\n"}
    &loadPaths($xml_conf);
    &readXmlJobs($jobs_confFile,1) if(!$conf_invalid{jobs_conf_filename});
}