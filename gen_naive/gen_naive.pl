use strict;
use Getopt::Long; 
use Cwd;
# this script takes a complete benchmark
# written with a software section/and a
# hls-able section and generate the 
# hls project, vivado top project and
# the sdk project


my $fileName;
my $dirName;

usage() if(@ARGV < 2 or
			!GetOptions('file=s'=>\$fileName,'dir=s'=>\$dirName));




unless(-e $fileName)
{
	print "File doesn't exist: $fileName\n";
	exit;
}
unless(-d $dirName)
{
	print "Directory $dirName does not exist. Create?\n";
	my $answer = getc();
	if($answer == 'y' || $answer == 'Y')
	{
		if(mkdir $dirName)
		{
			print "created directory $dirName\n";
		}
		else
		{
			print "cannot create dir $dirName\n";
			exit;
		}
	}
}
# now try to set up the dir structure
# dirName
#  |	|
# HLS  Vivado_top

mkdir "$dirName/HLS";
mkdir "$dirName/vivado_top";

my $backOffDir = getcwd;
print "backOff $backOffDir";
chdir "$dirName";
$dirName = `pwd`;
chop $dirName;
print "backOff $backOffDir";
print "complete dir name $dirName\n";


chdir ("$backOffDir") or die("soemhow not working\n");
my $nowDir = `pwd`;
print " after change to $backOffDir, we are at $nowDir\n";


# all set, now try to open that file
open (ORIGFILE, "<$fileName") or die("cannot open file $fileName\n");
my $hlsInputFile = "$dirName/HLS/hls.cpp";
open (HLSFILE, ">$hlsInputFile") or die ("cannot open file $hlsInputFile\n"); 
my $hlsTclFile = "$dirName/HLS/script.tcl";
open (HLSTCLFILE, ">$hlsTclFile") or die ("cannot open file $hlsTclFile\n"); 
my $hlsDirTclFile = "$dirName/HLS/directives.tcl";
open (HLSDIRTCLFILE, ">$hlsDirTclFile") or die ("cannot open file $hlsDirTclFile\n"); 
my $vivadoTopTclFile = "$dirName/vivado_top/vivado_top_create.tcl";
open (VIVADOTCLFILE, ">$vivadoTopTclFile") or die ("cannot open file $vivadoTopTclFile\n");

my $syn=0;
my $header=0;

my $functionName;
my %argNameType;

while(my $curLine = <ORIGFILE>)
{
	# now we try to find 
	# parse the file for comment section
	# //BEGIN_HLS_portion
	# //fun=foo
	# //argname=yyy,argtype=AXI4M
	# //argname=xxx,argtype=pipeline
	# //END_HEADER
	# and we will always have a setting and return
	# actual code
	# //END_HLS_portion  
	if($curLine =~ /\/\/\s*BEGIN_HLS_portion/)
	{
		$syn = 1;
		$header = 1;
	}
	elsif($curLine =~ /\/\/\s*END_HLS_portion/)
	{
		$syn = 0;
	}
		
	if($syn==1)
	{

		if($header==1)
		{
			if($curLine =~ /\/\/\s*fun=(.+)/)
			{
				# name of function is $1
				$functionName = $1;		
			}
			elsif($curLine =~ /\/\/\s*argname=([a-zA-Z0-9_]+)\s*,argtype=(AXI4M)/)
			{
				$argNameType{$1} = 	$2;
			}
			elsif($curLine =~ /\/\/\s*argname=([a-zA-Z0-9_]+)\s*,argtype=(pipeline)/)
			{
				$argNameType{$1} = 	$2;
			}
			elsif($curLine=~/\/\/\s*END_HEADER/)
			{
				$header = 0;
			}
		}
		else
		{
			print HLSFILE $curLine;
		}
	}
	
}

#now generate the tcl script for project generation
generateProjectTcl($functionName);
#now generate the tcl script for directive insertion
generateDirTcl(\%argNameType, $functionName);
#run vivado_hls to create the project, apply directives and such
my $curDir = `pwd`;
chop $curDir;
chdir("$dirName/HLS");
my $hlsDir = `pwd`;
chop $hlsDir;
system("vivado_hls -f script.tcl");
chdir($curDir);
#now generate the tcl script for vivado top
generateVivadoTop($functionName,"$dirName\/vivado_top",$hlsDir,\%argNameType);
chdir("$dirName/vivado_top");
system("vivado -mode batch -source vivado_top_create.tcl");



sub generateVivadoTop
{
	my $funcName = shift(@_);
	my $projectDirName = shift(@_);
	my $hlsTop = shift(@_);
	my $argRef = shift(@_);
	my %argHash = %$argRef;
		
	my $projectName = "${funcName}_top";

	print VIVADOTCLFILE "create_project $projectName $projectDirName\/$projectName -part xc7z020clg484-1\n";
	print VIVADOTCLFILE "set_property board em.avnet.com:zynq:zed:d [current_project]\n";
	print VIVADOTCLFILE "create_bd_design \"design_1\"\n";
	#import the ip
	print VIVADOTCLFILE "set_property ip_repo_paths $hlsTop\/$funcName [current_fileset]\n";
	print VIVADOTCLFILE "update_ip_catalog\n";
	printVivadoStartEndGroup("create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.3 processing_system7_0");
	print VIVADOTCLFILE "apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external \"FIXED_IO, DDR\" apply_board_preset \"1\" }  [get_bd_cells processing_system7_0]\n";
	
	printVivadoStartEndGroup("create_bd_cell -type ip -vlnv xilinx.com:hls:$funcName:1.0 ${funcName}_0");
	print VIVADOTCLFILE "apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master \"\/processing_system7_0\/M_AXI_GP0\" }  [get_bd_intf_pins ${funcName}_0\/S_AXI_CB]\n";
	
	# now we see if there are AXI4M stuff
	my @axi4MasterName;
	foreach(keys(%argHash))
	{
		my $curArgName =$_;
		if ($argHash{$curArgName} =~ /AXI4M/i)
		{
			push(@axi4MasterName, $curArgName);
		}
		
	}
	my $numMaster = scalar @axi4MasterName;
	if(  $numMaster gt 0)
	{
		printVivadoStartEndGroup("set_property -dict [list CONFIG.PCW_USE_S_AXI_ACP {1} CONFIG.PCW_USE_DEFAULT_ACP_USER_VAL {1}] [get_bd_cells processing_system7_0]");
		printVivadoStartEndGroup("create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0");
		printVivadoStartEndGroup("set_property -dict [list CONFIG.NUM_SI {$numMaster} CONFIG.NUM_MI {1} CONFIG.STRATEGY {2}] [get_bd_cells axi_interconnect_0]");		
		
		print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets processing_system7_0_FCLK_CLK0] [get_bd_pins axi_interconnect_0\/ACLK] [get_bd_pins processing_system7_0\/FCLK_CLK0]\n";
		print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets rst_processing_system7_0_100M_peripheral_aresetn] [get_bd_pins axi_interconnect_0\/ARESETN] [get_bd_pins rst_processing_system7_0_100M\/peripheral_aresetn]\n";
		# master reset/clk
		print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets processing_system7_0_FCLK_CLK0] [get_bd_pins axi_interconnect_0\/M00_ACLK] [get_bd_pins processing_system7_0\/FCLK_CLK0]\n";
		print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets rst_processing_system7_0_100M_peripheral_aresetn] [get_bd_pins axi_interconnect_0\/M00_ARESETN] [get_bd_pins rst_processing_system7_0_100M\/peripheral_aresetn]\n";



		# now for every axi master connect it to the ACP port through an interconnect
		my $portCount = 0;
		foreach(@axi4MasterName)
		{
			# got to set the master to cacheable first C_M_AXI_ _CACHE_VALUE
			my $curMasterName = uc $_;
			my $portNumStr;			
			if($portCount lt 10)
			{
				$portNumStr = "S0${portCount}";
			}
			else
			{
				$portNumStr = "S${portCount}";
			}
			printVivadoStartEndGroup("set_property -dict [list CONFIG.C_M_AXI_${curMasterName}_CACHE_VALUE {\"1111\"}] [get_bd_cells ${funcName}_0]");
			# now do the connection
			print VIVADOTCLFILE "connect_bd_intf_net [get_bd_intf_pins ${funcName}_0\/M_AXI_${curMasterName}] [get_bd_intf_pins axi_interconnect_0\/${portNumStr}_AXI]\n";
			print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets processing_system7_0_FCLK_CLK0] [get_bd_pins axi_interconnect_0\/${portNumStr}_ACLK] [get_bd_pins processing_system7_0\/FCLK_CLK0]\n";
			print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets rst_processing_system7_0_100M_peripheral_aresetn] [get_bd_pins axi_interconnect_0\/${portNumStr}_ARESETN] [get_bd_pins rst_processing_system7_0_100M\/peripheral_aresetn]\n";


			$portCount = $portCount+1;
		}
		print VIVADOTCLFILE	"connect_bd_intf_net [get_bd_intf_pins processing_system7_0\/S_AXI_ACP] [get_bd_intf_pins axi_interconnect_0\/M00_AXI]\n";
		print VIVADOTCLFILE "assign_bd_address\n";
		print VIVADOTCLFILE "connect_bd_net -net [get_bd_nets processing_system7_0_FCLK_CLK0] [get_bd_pins processing_system7_0\/S_AXI_ACP_ACLK] [get_bd_pins processing_system7_0\/FCLK_CLK0]\n";
		printVivadoStartEndGroup("set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {150.000000}] [get_bd_cells processing_system7_0]
");		
		print VIVADOTCLFILE "validate_bd_design\n";
		print VIVADOTCLFILE "save_bd_design\n";
		print VIVADOTCLFILE "make_wrapper -files [get_files $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/design_1.bd] -top\n";
		print VIVADOTCLFILE "add_files -norecurse $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/hdl\/design_1_wrapper.v\n";
		print VIVADOTCLFILE "update_compile_order -fileset sources_1\n";
		print VIVADOTCLFILE "update_compile_order -fileset sim_1\n";
		print VIVADOTCLFILE "launch_runs impl_1 -to_step write_bitstream\n";
		print VIVADOTCLFILE "wait_on_runs\n";
		print VIVADOTCLFILE "open_run impl_1\n";
		print VIVADOTCLFILE "export_hardware [get_files $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/design_1.bd] [get_runs impl_1] -bitstream\n";
		print VIVADOTCLFILE "launch_sdk -bit $projectDirName\/$projectName\/$projectName.sdk/SDK/SDK_Export/hw/design_1_wrapper.bit -workspace $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export -hwspec $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\/hw\/design_1.xml\n";


		





	}
	




}
sub printVivadoStartEndGroup
{
	my $actualStr = shift(@_);
	print VIVADOTCLFILE "startgroup\n";
	print VIVADOTCLFILE "$actualStr\n";
	print VIVADOTCLFILE "endgroup\n";
	
}



sub generateDirTcl
{
		
	my $argRef = shift(@_);
	my $funcName = shift(@_);	
	my %argHash = %$argRef;
	print HLSDIRTCLFILE "set_directive_interface -mode ap_hs \"$funcName\" settings\n";
	print HLSDIRTCLFILE "set_directive_resource -core AXI4LiteS -metadata {-bus_bundle cb} \"$funcName\" return\n";
	print HLSDIRTCLFILE "set_directive_resource -core AXI4LiteS -metadata {-bus_bundle cb} \"$funcName\" settings\n";
	foreach(keys(%argHash))
	{
		my $curArgName =$_;
		if ($argHash{$curArgName} =~ /AXI4M/i)
		{
			print HLSDIRTCLFILE "set_directive_interface -mode ap_bus \"$funcName\" $curArgName\n";
			print HLSDIRTCLFILE "set_directive_resource -core AXI4M \"$funcName\" $curArgName\n";
		}
		elsif($argHash{$curArgName} =~ /pipeline/i)
		{  
			print HLSDIRTCLFILE "set_directive_pipeline \"$funcName\/$curArgName\"\n";

		}
		print "\n";
	}


}

sub generateProjectTcl
{
	my $func = shift(@_);
	print HLSTCLFILE "open_project -reset $func\n";
	print HLSTCLFILE "set_top $func\n";
	print HLSTCLFILE "add_files hls.cpp\n";
	print HLSTCLFILE "open_solution -reset \"solution1\"\n";
	print HLSTCLFILE "set_part {xc7z020clg484-1}\n";
	print HLSTCLFILE "create_clock -period 8 -name default\n";
	print HLSTCLFILE "set_clock_uncertainty 0.5\n";
	print HLSTCLFILE "source \"directives.tcl\"\n";
	print HLSTCLFILE "csynth_design\n";
	#cosim_design -trace_level none
	print HLSTCLFILE "export_design -format ip_catalog -description \"An IP generated by Vivado HLS\" -vendor \"xilinx.com\" -library \"hls\" -version \"1.0\"\n";
	print HLSTCLFILE "export_design -format pcore -version \"1.00.a\" -use_netlist none\n";
	print HLSTCLFILE "exit\n";
}
sub usage
{
	print "usage: --file input_file_name --dir output_dir_name\n";
}


