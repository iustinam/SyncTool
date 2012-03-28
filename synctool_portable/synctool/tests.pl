use strict;
use warnings;
use Win32::File;
use Data::Dumper;
use File::Spec;
use Storable qw/nstore retrieve/;
use Carp;

my $testfile="test.txt";
my $logfile="testlog.txt";
my $testDump="testdump.txt";

use constant{
 
};
my $attr_types={
    #'COMPRESSED'=>COMPRESSED,
    'OFFLINE'=>OFFLINE,
    'SYSTEM'=>SYSTEM,
    'TEMPORARY'=>TEMPORARY,
    'ARCHIVE'=>ARCHIVE,
    'HIDDEN'=>HIDDEN,
    'READONLY'=>READONLY,
    'NORMAL'=>NORMAL};#DIRECTORY);
my $LOG;
#src/dest file/folder 

&main();

# sets all types of attrs on some random selected files from source
sub setAttr{
    #print "######### some testing on deleting files with diff attrs set\n";
    my ($d_path,$setattr)=@_ ;
    my $attrs;
    Win32::File::SetAttributes($d_path,0|$setattr);
    Win32::File::GetAttributes($d_path,$attrs);
    if ( $attrs&$setattr){ 
        #print "ok: setting $d_path $setattr\n";
        return 1;
    }else{
        
        return 0;
    }
    #unlink($d_path)&&print("deleted COMPRESSED\n") or print "test: $!\n";  
    #print "######## ended testing\n";
}

sub isAttrSet{
    my ($d_path,$setattr)=@_ ;
    die("isAttrSet: no path\n") if(not $d_path);
    die("isAttrSet: no setattr\n") if(not $setattr);
    my $attrs;
    Win32::File::GetAttributes($d_path,$attrs);
    if ( $attrs&$setattr){ 
        return 1;
    }else{
        return 0;
    }
}

sub setRandAttrs{
     #setez pe fis/dir rand attr si fac un nstore pt care au fost selectate si ce attr
     my ($dir)=@_;
     print $LOG "######### Setting rand attrs on files: $dir\n";
    
     my (@files,@dirs,$randFile,$randDir,$nofiles,$nodirs);
     my %items;
     opendir(D,$dir) or print "ERR: opendir $dir\n";
     map {
         my $fullname=File::Spec->catfile($dir,$_);
         if(/\.\.?$/){}
         else{
             if(-f $fullname){push @files,$fullname;}
             if(-d $fullname){push @dirs,$fullname;}   
         } 
     } readdir(D);
     #print "Files: ".Dumper(@files)."\n";
     #print "Dirs: ".Dumper(@dirs)."\n";
     $nofiles=scalar @files;
     $nodirs=scalar @dirs;
     if($nofiles<(scalar (keys %$attr_types))){
         print "ERR: not enough files in $dir\n";
         return;   
     }
     if($nodirs<(scalar (keys %$attr_types))){
         print "ERR: not enough files in $dir\n";
         return;   
     }
     
     foreach(keys %$attr_types){
        my $nok=1;
        while($nok){
            $randFile=$files[int(rand($nofiles))-1];
            if(!$items{$randFile}){
                if(setAttr($randFile,$attr_types->{$_})){
                    $items{$randFile}=$_;
                }else{
                    print "ERR: setting $randFile $_\n";
                }
                $nok=0;
            }
        }
        $nok=1;
        
        if(($_~~'TEMPORARY')||($_~~'NORMAL')){
            next;   
        }
        while($nok){
            $randDir=$dirs[int(rand($nodirs))-1];
            if(!$items{$randDir}){
                if(setAttr($randDir,$attr_types->{$_})){
                    $items{$randDir}=$_;
                }else{
                    print "ERR: setting $randDir $_\n";
                }
                $nok=0;
            }
        }
     }
     print "Items: ".Dumper(\%items)."\n";
     
     nstore \%items,$testDump;
}
sub printAllAttrs{
    my ($d_path)=@_;
    my $attrs;
    print "$d_path has: ";
    #print Dumper(keys %$attr_types);
    foreach(keys %$attr_types){
        Win32::File::GetAttributes($d_path,$attrs);
        my $a=$attr_types->{$_};
        if ( $attrs &$a ){ 
            print $_." ";
        }
    }
    print "\n";
}

sub vrfyAttrs{
    my $items=retrieve($testDump);
    print "Items: ".Dumper($items)."\n";
    foreach(keys %$items){
        if(isAttrSet($_,$attr_types->{$items->{$_}})){
            print "ok: $_ has $items->{$_}\n";
        }else{
            print "ERR: $_ is NOT $items->{$_}\n";
        }   
    }
}

#generate n dirs with each attr type and contents with no attr(vrfy sync can delete)
sub setupDirsWithAttrsInsideDir{
    my ($dir)=@_;
    
    my $newDir;
    print $LOG "######### Setting up ditrectories with attributes $dir\n";
    foreach(keys %$attr_types){
        if(($_~~'TEMPORARY')||($_~~'NORMAL')){
            next;   
        }
        my $nok=1;
        
        $newDir=File::Spec->catdir($dir,$_);
        mkdir($newDir) or die("Cannot create $newDir\n");
        # SET ATTR
        if(setAttr($newDir,$attr_types->{$_})){
            print "$newDir was set to : $_\n";    
        }else{
            print "ERR: $newDir was NOT set to : $_\n";
        }
        
        #PUT DIR CONTENT
        my $f=File::Spec->catfile($newDir,"test.txt");
        open( H, '>', $f ) or die "err: Cannot create test file $f $!\n";
        print H "bau";
        close H;
    }
}

#stat 

sub setupCaseSensitiveDirToFile{
    # create lowercase dir in src, uppercase file in dst
    my ($sdir,$ddir)=@_;
    opendir(D,$sdir) or print "ERR: opendir $sdir\n";
    mkdir(File::Spec->catdir($sdir,"NEWDIRTOFILE")) or croak("Cannot create dir $!\n");
    closedir(D);
    
    opendir(D,$ddir) or print "ERR: opendir $ddir\n";
    open( H, '>', File::Spec->catfile($ddir,"newdirtofile") ) or croak "err: Cannot create test file  $!\n";
    print H "bau";
    close H;
    closedir(D);
}

sub setupCaseSensitiveFileToDir{
    # create lowercase file in src, uppercase dir in dst
    my ($sdir,$ddir)=@_;
    opendir(D,$sdir) or print "ERR: opendir $sdir\n";
    open( H, '>', File::Spec->catfile($sdir,"NEWFILETODIR") ) or croak "err: Cannot create test file  $!\n";
    print H "bau";
    close H;
    closedir(D);
    
    opendir(D,$ddir) or print "ERR: opendir $ddir\n";
    mkdir(File::Spec->catdir($ddir,"newfiletodir")) or croak("Cannot create dir $!\n");
    closedir(D);
}

sub setupCaseSensitiveDirToDir{
    # create lowercase file in src, uppercase dir in dst
    my ($sdir,$ddir)=@_;
    opendir(D,$sdir) or print "ERR: opendir $sdir\n";
    mkdir(File::Spec->catdir($sdir,"NEWDIR")) or croak("Cannot create dir $!\n");
    closedir(D);
    
    opendir(D,$ddir) or print "ERR: opendir $ddir\n";
    mkdir(File::Spec->catdir($ddir,"newdir")) or croak("Cannot create dir $!\n");
    closedir(D);
}

sub setupCaseSensitiveFileToFile{
    # create lowercase file in src, uppercase dir in dst
    my ($sdir,$ddir)=@_;
    opendir(D,$sdir) or print "ERR: opendir $sdir\n";
    open( H, '>', File::Spec->catfile($sdir,"NEWFILE") ) or croak "err: Cannot create test file  $!\n";
    print H "bau";
    close H;
    closedir(D);
    
    opendir(D,$ddir) or print "ERR: opendir $ddir\n";
    open( H, '>', File::Spec->catfile($ddir,"newfile") ) or croak "err: Cannot create test file  $!\n";
    print H "bau";
    close H;
    closedir(D);
}
sub main{
    #setez pe fis rand attr si fac un nstore pt care au fost selectate si ce attr
    open (F,'<',$testfile) or die "Could not open $testfile\n"; 
    open ($LOG,'>',$logfile) or die "Could not open $logfile\n"; 
    while(<F>){
        print $_."\n"; 
        chomp($_);
        #setRandAttrs(File::Spec->catdir($_));  
        #vrfyAttrs();
        #printAllAttrs("D:\\Perl\\bin\\perl.exe");
        #setupDirsWithAttrsInsideDir(File::Spec->catdir($_));
        
        setupCaseSensitiveDirToFile($ARGV[0],$ARGV[1]);
        setupCaseSensitiveFileToDir($ARGV[0],$ARGV[1]);
        setupCaseSensitiveDirToDir($ARGV[0],$ARGV[1]);
        setupCaseSensitiveFileToFile($ARGV[0],$ARGV[1]);
    }   
    close F;
    close $LOG;
}










