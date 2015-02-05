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
my $unrunHLSGen = 0;
my $unrunVivado = 0;
my $unrunXSdk = 0;
usage() if(@ARGV < 2 or
			!GetOptions('file=s'=>\$fileName,
						'dir=s'=>\$dirName,
						'noHLS'=>\$unrunHLSGen,
						'noVivado'=>\$unrunVivado,
						'noXSdk'=>\$unrunXSdk));




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
unless($unrunHLSGen)
{
	open (HLSFILE, ">$hlsInputFile") or die ("cannot open file $hlsInputFile\n"); 
}
my $hlsTclFile = "$dirName/HLS/script.tcl";
unless($unrunHLSGen)
{
	open (HLSTCLFILE, ">$hlsTclFile") or die ("cannot open file $hlsTclFile\n"); 
}
my $hlsDirTclFile = "$dirName/HLS/directives.tcl";
unless($unrunHLSGen)
{
	open (HLSDIRTCLFILE, ">$hlsDirTclFile") or die ("cannot open file $hlsDirTclFile\n"); 
}
my $vivadoTopTclFile = "$dirName/vivado_top/vivado_top_create.tcl";
unless($unrunVivado)
{
	open (VIVADOTCLFILE, ">$vivadoTopTclFile") or die ("cannot open file $vivadoTopTclFile\n");
}
my $xsdkTclFile = "$dirName/xsdk_setup.tcl";
unless($unrunXSdk)
{
	open (XSDKTCLFILE, ">$xsdkTclFile") or die ("cannot open file $xsdkTclFile\n");
}
my $xsdkTclBuildFile = "$dirName/xsdk_build.tcl";
unless($unrunXSdk)
{
	open (XSDKTCLBUILDFILE, ">$xsdkTclBuildFile") or die ("cannot open file $xsdkTclBuildFile\n");
}



my $syn=0;
my $header=0;

my $functionName="";
my %argNameType;

my @runswFunc;
my $swSyn=0;

my @swArgs;
my $argSyn=0;


my $extraStr="";
my $main = 0;
my @setupMainStr = "";


my $timerSetupMain = "\tinit_platform();\n\tTimerInstancePtr = &Timer;\n\tint Status;\n\t// Initialize timer counter\n\tConfigPtr = XScuTimer_LookupConfig(TIMER_DEVICE_ID);"; 
$timerSetupMain="$timerSetupMain\n\tif(!ConfigPtr)\n\t	xil_printf(\"scutimer cant be found\\n\");\n\tStatus = XScuTimer_CfgInitialize(TimerInstancePtr, ConfigPtr,ConfigPtr->BaseAddr);";
$timerSetupMain="$timerSetupMain\n\tif(Status !=XST_SUCCESS)\n\t{\n\t	xil_printf(\"scutimer initialization fail\");\n\t}\n\tXScuTimer_LoadTimer(TimerInstancePtr, TIMER_LOAD_VALUE);";
$timerSetupMain="$timerSetupMain\n\tXScuTimer_Start(TimerInstancePtr);\n\tXScuTimer_RestartTimer(TimerInstancePtr);\n\tCntValue1 = XScuTimer_GetCounterValue(TimerInstancePtr);";
$timerSetupMain="$timerSetupMain\n\txil_printf(\"calibrate: \%d clock cycles\\r\\n\", TIMER_LOAD_VALUE-CntValue1);\n\tXScuTimer_RestartTimer(TimerInstancePtr);\n\tCntValue1 = XScuTimer_GetCounterValue(TimerInstancePtr);";
$timerSetupMain="$timerSetupMain\n\txil_printf(\"calibrate: \%d clock cycles\\r\\n\", TIMER_LOAD_VALUE-CntValue1);\n\tXScuTimer_RestartTimer(TimerInstancePtr);\n\tCntValue1 = XScuTimer_GetCounterValue(TimerInstancePtr);";
$timerSetupMain="$timerSetupMain\n\txil_printf(\"calibrate: \%d clock cycles\\r\\n\", TIMER_LOAD_VALUE-CntValue1);\n";

my $callArgument;

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
		print HLSFILE "#define HLS\n";
	}
	elsif($curLine =~ /\/\/\s*END_HLS_portion/)
	{
		$syn = 0;
	}
	elsif($curLine =~ /\/\/\s*BEGIN_SW/)
	{
		$swSyn = 1;
		next;
	}
	elsif($curLine =~ /\/\/\s*END_SW/)
	{
		$swSyn = 0;
	}
	elsif($curLine =~ /int\s+main/  || $curLine =~ /void\s+main/)
	{
		$main = 1;
		push(@setupMainStr,"#define RUN_ACC\n");
	}


	if($syn==1)
	{
		$extraStr = "${extraStr}$curLine";
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
	elsif($swSyn==1)
	{
		# non syn part -- all these stuff should be copied over , with tags to be replaced by writting primitives
		# what are these? run_sw function
		# from here the run_hw can be generated -- all the argument to the run_sw should be converted to u32 and written
		# to the setting port of the synthesized engien
		
		#we have to parse the argument for the sw routine
		# we check for (		
		push(@runswFunc, $curLine);
		if($argSyn == 0)
		{
			if($curLine=~/\((.*)\)/)
			{
				$argSyn=1;
				my $allArgs = $1;
				while($allArgs =~ s/(.*),//)
				{
					push(@swArgs, $1);
				}
				unless($allArgs =~ /^\s*$/)
				{
					push(@swArgs, $allArgs);
				}
			}
		}
	}
	elsif($main)
	{
		if($curLine =~ /\/\/\s*INIT_TIMER/)
		{
			push(@setupMainStr ,$timerSetupMain);
		}
		elsif($curLine =~ /\/\/\s*START_TIMER/)
		{
			push(@setupMainStr, "\n\tXScuTimer_RestartTimer(TimerInstancePtr);\n");
		}
		elsif($curLine =~ /\/\/\s*END_TIMER/)
		{
			push(@setupMainStr, "\n\tCntValue1 = XScuTimer_GetCounterValue(TimerInstancePtr);\n\txil_printf(\"print: \%d clock cycles for software computation\\r\\n\", TIMER_LOAD_VALUE-CntValue1);\n");
		}
		elsif($curLine =~ /\/\/\s*RUN_HW(.*)/)
		{
			#extract the argument name and concat them to the calls
			$callArgument = $1;
			push(@setupMainStr,"RUN_HW");
		}
		else
		{
			push(@setupMainStr,${curLine});
		}
	}
}


unless($unrunHLSGen)
{
	#now generate the tcl script for project generation
	generateProjectTcl($functionName);
	#now generate the tcl script for directive insertion
	generateDirTcl(\%argNameType, $functionName);
}
	#run vivado_hls to create the project, apply directives and such
my $curDir = `pwd`;
chop $curDir;
chdir("$dirName/HLS");
my $hlsDir = `pwd`;
chop $hlsDir;
unless($unrunHLSGen)
{
	system("vivado_hls -f script.tcl");
}
chdir($curDir);

unless($unrunVivado)
{
	#now generate the tcl script for vivado top
	generateVivadoTop($functionName,"$dirName\/vivado_top",$hlsDir,\%argNameType);
	chdir("$dirName/vivado_top");
	system("vivado -mode batch -source vivado_top_create.tcl");
	chdir($curDir);
}
unless($unrunXSdk)
{
	generateXsdkTclSetup($functionName,"$dirName\/vivado_top");
	generateXsdkTclBuild($functionName,"$dirName\/vivado_top");	
	
	#system("xsdk -batch -source $xsdkTclFile");
	generateSoftware($functionName,"$dirName\/vivado_top");
	#got to copy over the pcore headers and stuff
	
	#system("xsdk -batch -source $xsdkTclBuildFile");
	
}



sub generateSoftware
{
	# we drop in all the dummy stuff to drive the synthesized accelerator
	# and then copy the file over to replace helloworld.c
	# then we build
	my $funcName = shift(@_);
	my $projectDirName = shift(@_);
	my $projectName = "${funcName}_top";

	my $srcToModify = "helloworld.c";#"$projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\/naive_${funcName}_run\/src\/helloworld.c";
	
	open (CSRC, ">$srcToModify") or die("cannot open the c file\n");
	
	print CSRC "#include <stdio.h>\n#include \"platform.h\"\n#include \"xscutimer.h\"\n#include \"xparameters.h\"\n#include \"xil_printf.h\"\n#include \"xscugic.h\"\n#include \"xdmaps.h\"\n";
	print CSRC "#include \"x${funcName}.h\"\n";
	#print CSRC "#include \"x${funcName}_cb.h\"\n";
	print CSRC "#define TIMER_LOAD_VALUE 0xFFFFFFFF\n#define TIMER_DEVICE_ID	XPAR_SCUTIMER_DEVICE_ID\n";
	# maybe extra defs and stuff
	print CSRC "$extraStr\n";

	# replace the funcName's first letter to upper
	my $fl = substr $funcName, 0, 1;
	$fl = uc $fl;
	my $flOrig = substr $funcName, 1;
	my $flUpped = "${fl}${flOrig}";
	print CSRC "X${flUpped} ${funcName}_dev;\n";
	my $entireUpped = uc $funcName;
	print CSRC "X${flUpped}_Config ${funcName}_config = {\n\t0,XPAR_${entireUpped}_0_S_AXI_CB_BASEADDR\n};\nXScuTimer Timer;\nvolatile u32 CntValue1;\nXScuTimer_Config *ConfigPtr;\nXScuTimer *TimerInstancePtr;\n";
	
		
	print CSRC "void setupHw${funcName}()\n{\n	int status = X${flUpped}_Initialize(&${funcName}_dev, &${funcName}_config);\n	if(status !=XST_SUCCESS)\n		xil_printf(\"cannot initialize acc\\n\\r\");\n}\n\n";
	print CSRC "int writeToSettingAddress(u32 Data)\n";
	print CSRC "{\n";
	print CSRC "	X${flUpped}_SetSettings(&${funcName}_dev, Data);\n";
	print CSRC "	X${flUpped}_SetSettingsVld(&${funcName}_dev);\n";
	print CSRC "	Data = X${flUpped}_GetSettingsVld(&${funcName}_dev);\n";
	print CSRC "	int m =0;\n";
	print CSRC "	while(Data != 0 && m <100)\n";
	print CSRC "	{\n";
	print CSRC "		Data = X${flUpped}_GetSettingsVld(&${funcName}_dev);\n";
	print CSRC "		m++;\n";
	print CSRC "	}\n";
	print CSRC "	return Data;\n";
	print CSRC "}\n";


	# now print out the run sw thing
	foreach(@runswFunc)
	{
		print CSRC $_;
	}
	# now we need to generate the setup hw thing
	print CSRC "\nint runHw${funcName}(";
	my $s = 1;
	foreach(@swArgs)
	{
		if($s)
		{
			$s=0;
		}
		else
		{
			print CSRC ",";
		}
		print CSRC $_;
		
		
	}
	print CSRC ")\n{\n";
	# writing each and every arg into the thing
	print CSRC "\tint m;\n";
	print CSRC "\tX${flUpped}_Start(&${funcName}_dev);\n";
	print CSRC "\tu32 Data;\n";
	my $numEle = scalar @swArgs;
	my $timerStr = generateStrForTiming($flUpped, $funcName);
	if($numEle == 0)
	{
		print CSRC "XScuTimer_RestartTimer(TimerInstancePtr);\n";
		print CSRC "$-type app naive_${funcName}_runtimerStr\n";	

	}
	else
	{
		my $eleInd;
		for($eleInd=0; $eleInd < $numEle-1; $eleInd = $eleInd+1)
		{
			my $curArg = $swArgs[$eleInd];
			my ($argType,$argName)  = getNameFromFuncArg($curArg);
			generateDataCast($argType, $argName);
			print CSRC "\tData = writeToSettingAddress(Data);\n";
			print CSRC "\tif(Data == 1)\n";
			print CSRC "\t{\n";
			print CSRC "\t	xil_printf(\"cannot write $argName \\n\\r\");\n";
			print CSRC "\t	return 1;\n";
			print CSRC "\t}\n";
		}
		# now is the last dude
		my $lastArg = $swArgs[$eleInd];
		my ($argType,$argName)  = getNameFromFuncArg($lastArg);
		generateDataCast($argType, $argName);
		
		print CSRC "	X${flUpped}_SetSettings(&${funcName}_dev, Data);\n";
		print CSRC "	XScuTimer_RestartTimer(TimerInstancePtr);\n";
		print CSRC "	X${flUpped}_SetSettingsVld(&${funcName}_dev);\n";
		print CSRC "	Data = X${flUpped}_GetSettingsVld(&${funcName}_dev);\n";
		print CSRC "	m =0;\n";
		print CSRC "	while(Data != 0 && m <100)\n";
		print CSRC "	{\n";
		print CSRC "		Data = X${flUpped}_GetSettingsVld(&${funcName}_dev);\n";
		print CSRC "		m++;\n";
		print CSRC "	}\n";
		print CSRC "	if(Data ==1)\n";
		print CSRC "	{\n";
		print CSRC "		xil_printf(\"cannot write $argName to acc\\n\\r\");\n";
		print CSRC "		return 1;\n";
		print CSRC "	}\n";
		print CSRC "$timerStr\n";
	}	
	
	print CSRC "}\n";

	# now this part is the initialization and setup memory space before everything runs
	foreach(@setupMainStr)
	{
		my $curL = $_;
		if($curL =~ /^RUN_HW$/)
		{
			print CSRC "\tsetupHw${funcName}();\n";
			print CSRC "\trunHw${funcName}${callArgument};\n";
		}
		else
		{
			print CSRC $curL;
		}
	}

}

sub generateDataCast
{
	my $argType = shift(@_);
	my $argName = shift(@_);
	my $isPtr = 0;		
	if($argType =~ /\*/)
	{
		$isPtr = 1;
	}
	if($isPtr == 1)
	{
		print CSRC "\tData = (u32)$argName>>2;\n";
	}
	else
	{
		print CSRC "\tData = (u32)$argName;\n";
	}
}

sub generateStrForTiming
{
	my $flUpped = shift (@_);
	my $funcName = shift(@_);
	my $rtStr = 	  "\tm=0;\n\twhile(!X${flUpped}_IsDone(&${funcName}_dev) && m<500000)";
	$rtStr = "$rtStr\n\t{";
	$rtStr = "$rtStr\n	\tm++;";
	$rtStr = "$rtStr\n\t}";
	$rtStr = "$rtStr\n\tCntValue1 = XScuTimer_GetCounterValue(TimerInstancePtr);";

	$rtStr = "$rtStr\n\tif(m<500000)";
	$rtStr = "$rtStr\n\t{";
	$rtStr = "$rtStr\n	\txil_printf(\"done after \%d wait iter\\n\\r\", m);";
	$rtStr = "$rtStr\n	\txil_printf(\"consumed time is \%d\\n\\r\", TIMER_LOAD_VALUE - CntValue1);";
	$rtStr = "$rtStr\n\t}";
 	return $rtStr;
}

sub getNameFromFuncArg
{
	my $funcArgStr = shift(@_);

	$funcArgStr =~ s/^\s*(.*)/$1/;
	$funcArgStr =~ s/(.*)\s+$/$1/;
	#my $str = $funcArgStr;
	if ($funcArgStr =~ /(\S+)\s+(\S+)$/) 	
	{
		return ($1,$2);
	}
	else
	{
		die ("cannot parse the func arg $funcArgStr\n");

	}
}		

sub generateXsdkTclSetup
{
	my $funcName = shift(@_);
	my $projectDirName = shift(@_);
	my $projectName = "${funcName}_top";
	print XSDKTCLFILE "set_workspace $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\n";
	print XSDKTCLFILE "create_project -type hw -name hw_platform -hwspec $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\/hw\/design_1.xml\n";
	print XSDKTCLFILE "create_project -type bsp -name bsp_0 -hwproject hw_platform -proc ps7_cortexa9_0 -os standalone\n";
	print XSDKTCLFILE "create_project -type app -name naive_${funcName}_run -hwproject hw_platform -proc ps7_cortexa9_0 -os standalone -lang C -app {Hello World} -bsp bsp_0\n";
	print XSDKTCLFILE "exit\n";
	
}

sub generateXsdkTclBuild
{
	my $funcName = shift(@_);
	my $projectDirName = shift(@_);
	my $projectName = "${funcName}_top";

	print XSDKTCLBUILDFILE "set_workspace $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\n";
	print XSDKTCLBUILDFILE "build\n";

}

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
		printVivadoStartEndGroup("set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {150.000000}] [get_bd_cells processing_system7_0]");		
		print VIVADOTCLFILE "validate_bd_design\n";
		print VIVADOTCLFILE "save_bd_design\n";
		print VIVADOTCLFILE "make_wrapper -files [get_files $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/design_1.bd] -top\n";
		print VIVADOTCLFILE "add_files -norecurse $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/hdl\/design_1_wrapper.v\n";
		print VIVADOTCLFILE "update_compile_order -fileset sources_1\n";
		print VIVADOTCLFILE "update_compile_order -fileset sim_1\n";
		print VIVADOTCLFILE "launch_runs impl_1 -to_step write_bitstream\n";
		print VIVADOTCLFILE "wait_on_run impl_1\n";
		print VIVADOTCLFILE "open_run impl_1\n";
		print VIVADOTCLFILE "export_hardware [get_files $projectDirName\/$projectName\/$projectName.srcs\/sources_1\/bd\/design_1\/design_1.bd] [get_runs impl_1] -bitstream\n";
		#print VIVADOTCLFILE "launch_sdk -bit $projectDirName\/$projectName\/$projectName.sdk/SDK/SDK_Export/hw/design_1_wrapper.bit -workspace $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export -hwspec $projectDirName\/$projectName\/$projectName.sdk\/SDK\/SDK_Export\/hw\/design_1.xml\n";


		





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
	print "usage: --file input_file_name --dir output_dir_name <--noHLS> <--noVivado> <--noXSdk>\n";
}


