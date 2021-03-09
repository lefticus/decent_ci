# frozen_string_literal: true

def processor_count
  os_name = RbConfig::CONFIG['target_os']
  if os_name.match(/mingw|mswin/)
    require 'win32ole'
    result = WIN32OLE.connect('winmgmts://').ExecQuery('select NumberOfLogicalProcessors from Win32_Processor')
    result.to_enum.collect(&:NumberOfLogicalProcessors).reduce(:+)
  elsif File.readable?('/proc/cpuinfo')
    IO.read('/proc/cpuinfo').scan(/^processor/).size
  elsif File.executable?('/usr/bin/hwprefs')
    IO.popen('/usr/bin/hwprefs thread_count').read.to_i
  elsif File.executable?('/usr/sbin/psrinfo')
    IO.popen('/usr/sbin/psrinfo').read.scan(/^.*on-*line/).size
  elsif File.executable?('/usr/sbin/ioscan')
    IO.popen('/usr/sbin/ioscan -kC processor') do |out|
      out.read.scan(/^.*processor/).size
    end
  elsif File.executable?('/usr/sbin/pmcycles')
    IO.popen('/usr/sbin/pmcycles -m').read.count("\n")
  elsif File.executable?('/usr/sbin/lsdev')
    IO.popen('/usr/sbin/lsdev -Cc processor -S 1').read.count("\n")
  elsif File.executable?('/usr/sbin/sysconf') && os_name =~ /irix/i
    IO.popen('/usr/sbin/sysconf NPROC_ONLN').read.to_i
  elsif File.executable?('/usr/sbin/sysctl')
    IO.popen('/usr/sbin/sysctl -n hw.ncpu').read.to_i
  elsif File.executable?('/sbin/sysctl')
    IO.popen('/sbin/sysctl -n hw.ncpu').read.to_i
  else
    warn("Unknown platform: #{RbConfig::CONFIG['target_os']}")
    warn('Assuming 1 processor.')
    1
  end
end
