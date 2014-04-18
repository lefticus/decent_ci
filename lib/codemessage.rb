# encoding: UTF-8 

# warnings and errors from code compilation
class CodeMessage
  include Comparable
  attr_reader :filename
  attr_reader :linenumber
  attr_reader :colnumber
  attr_reader :messagetype
  attr_reader :message

  def initialize(filename, linenumber, colnumber, messagetype, message)
    @filename = filename
    @linenumber = linenumber
    @colnumber = colnumber
    @messagetype = messagetype
    @message = message
  end

  def is_warning
    @messagetype =~ /.*warn.*/i
  end

  def is_error
    @messagetype =~ /.*err.*/i
  end

  def inspect
    hash = {}
    instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
    return hash
  end

  def hash 
    return inspect.hash
  end

  def eql?(other)
    return (self <=> other) == 0
  end

  def <=> (other)
    f = @filename <=> other.filename
    l = @linenumber.to_i <=> other.linenumber.to_i
    c = @colnumber.to_i <=> other.colnumber.to_i
    mt = @messagetype <=> other.messagetype
    m = @message <=> other.message

    if f != 0 
      return f
    elsif l != 0
      return l
    else 
      return c
    end
  end

end

