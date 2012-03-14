#!usr/bin/perl -w
use File::Copy;
use File::Spec;
use File::Basename;
use Cwd;
use Win32;

#path = File::Spec->catfile('\\\\rbgs392x\did01524\SW\TestSyncTool\mmpenv.MMP_Environment_for_DS_Client\MsVisualStudio2005+Sp1\Program Files\Microsoft Visual Studio 8\SDK\v2.0\QuickStart\aspnet\samples\security\logincontrols_cs\App_Themes\SmokeAndGlass\Images\smokeandglass_brownfadetop.gif');
#File::Copy::copy($path,"err.gif") or die "cant copy $! \n";
#die();
#$to=File::Spec->catfile('\\\\?\iad3488d\tcp_software\TestSyncTool\mmpenv.MMP_Environment_for_DS_Client\MsVisualStudio2005+Sp1\Program Files\Microsoft Visual Studio 8\SDK\v2.0\QuickStart\aspnet\samples\security\logincontrols_vb\App_Themes\SmokeAndGlass\Images\smokeandglass_brownfadetop.gif');

#die();

my $dir=getcwd;
my $path = File::Spec->catfile('\\\\rbgs392x\did01524\SW\TestSyncTool\mmpenv.MMP_Environment_for_DS_Client\MsVisualStudio2005+Sp1\Program Files\Microsoft Visual Studio 8\SDK\v2.0\QuickStart\aspnet\samples\security\logincontrols_cs\App_Themes\SmokeAndGlass\Images\smokeandglass_brownfadetop.gif');
my $to=File::Spec->catfile('\\\\iad3488d\tcp_software\TestSyncTool\mmpenv.MMP_Environment_for_DS_Client\MsVisualStudio2005+Sp1\Program Files\Microsoft Visual Studio 8\SDK\v2.0\QuickStart\aspnet\samples\security\logincontrols_vb\App_Themes\SmokeAndGlass\Images\smokeandglass_brownfadetop.gif');
my ($a,$b,$c)= File::Spec->splitpath($to);
my $parent =File::Spec->catdir($a,$b);

$shortpath = Win32::GetShortPathName($parent) or die($!);
print $shortpath."\n";
my $dest=File::Spec->catfile($shortpath,"smokeandglass_brownfadetop.gif");
print $dest."\n";
print eval(-s $dest)."\n";
#File::Copy::copy($path,$dest) or die "cant copy $! \n";
#File::Copy::copy($dest,'D:\of.gif') or die "cant copy $! \n";
die();

#my ($a,$b,$c)= File::Spec->splitpath($to);
chdir(File::Spec->catdir($a,$b)) or die "Cant chdir to $path $!";
my $aa=getcwd;
print $aa."\n";
File::Copy::copy($path,$c) or die "cant copy $! \n";
chdir($dir) or die "Cant chdir to $path $!";