# Copyright 2010-2016, Raphael Reitzig
# <code@verrech.net>
#
# This file is part of ltx2any.
#
# ltx2any is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ltx2any is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ltx2any. If not, see <http://www.gnu.org/licenses/>.

require 'rubygems'

class DependencyManager
  private
    @@dependencies = []

    def self.more_recent(v1, v2)
      v1i = v1.gsub(/[^\d]/, '').to_i
      v2i = v2.gsub(/[^\d]/, '').to_i
      return v1i > v2i ? v1 : v2
    end

    # which(cmd) :: string or nil
    #
    # Multi-platform implementation of "which".
    # It may be used with UNIX-based and DOS-based platforms.
    #
    # The argument can not only be a simple command name but also a command path
    # may it be relative or complete.
    #
    # From: http://stackoverflow.com/a/25563129/539599
    def self.which(cmd)
      raise ArgumentError.new("Argument not a string: #{cmd.inspect}") unless cmd.is_a?(String)
      return nil if cmd.empty?
      case RbConfig::CONFIG['host_os']
      when /cygwin/
        exts = nil
      when /dos|mswin|^win|mingw|msys/
        pathext = ENV['PATHEXT']
        exts = pathext ? pathext.split(';').select{ |e| e[0] == '.' } : ['.com', '.exe', '.bat']
      else
        exts = nil
      end
      if cmd[File::SEPARATOR] or (File::ALT_SEPARATOR and cmd[File::ALT_SEPARATOR])
        if exts
          ext = File.extname(cmd)
          if not ext.empty? and exts.any?{ |e| e.casecmp(ext).zero? } \
          and File.file?(cmd) and File.executable?(cmd)
            return File.absolute_path(cmd)
          end
          exts.each do |ext|
            exe = "#{cmd}#{ext}"
            return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
          end
        else
          return File.absolute_path(cmd) if File.file?(cmd) and File.executable?(cmd)
        end
      else
        paths = ENV['PATH']
        paths = paths ? paths.split(File::PATH_SEPARATOR).select{ |e| File.directory?(e) } : []
        if exts
          ext = File.extname(cmd)
          has_valid_ext = (not ext.empty? and exts.any?{ |e| e.casecmp(ext).zero? })
          paths.unshift('.').each do |path|
            if has_valid_ext
              exe = File.join(path, "#{cmd}")
              return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
            end
            exts.each do |ext|
              exe = File.join(path, "#{cmd}#{ext}")
              return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
            end
          end
        else
          paths.each do |path|
            exe = File.join(path, cmd)
            return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
          end
        end
      end
      nil
    end

  public

  
  def self.add(dep)
    if dep.kind_of?(Dependency)
      @@dependencies.push(dep)
    else
      raise "Illegal parameter #{dep.to_s}"
    end
  end
  
  
  def self.list(type: :all, source: :all, relevance: :all)
    @@dependencies.select { |d|     
         (type == :all      || d.type == type           || (type.kind_of?(Array) && type.include?(d.type)))\
      && (source == :all    || d.source == source       || (d.source.kind_of?(Array) && d.source.include?(source)))\
      && (relevance == :all || d.relevance == relevance || (relevance.kind_of?(Array) && relevance.include?(d.relevance)))
    }
  end 
  

  def self.to_s
    @@dependencies.map { |d| d.to_s }.join("\n")
  end
end



class MissingDependencyError < StandardError; end



class Dependency
  def initialize(name, type, source, relevance, reason = '', version = nil)
    if ![:gem, :binary, :file].include?(type)
      raise "Illegal dependency type #{type.to_s}"
    elsif source != :core && (!source.kind_of?(Array) || ![:core, :extension, :engine].include?(source[0]) )
      raise "Illegal source #{source.to_s}"
    elsif ![:recommended, :essential].include?(relevance)
      raise "Illegal relevance #{relevance.to_s}"
    end
    if type != :gem && !(version.nil? || version.empty?)
      # Should not happen in production
      puts 'Developer warning: versions of binaries and files are not checked!'
    end
    
    @name = name
    @type = type
    @source = source.kind_of?(Array) ? source : [source, '']
    @relevance = relevance
    @reason = reason
    @version = version
    @available = nil
    
    DependencyManager.add(self)
  end
  
  public
  
  def available?
    if @available.nil?
      @available = case @type
        when :gem 
          begin
            gem "#{@name}"
            require @name
            true
          rescue Gem::LoadError
            false
          end
        when :binary
          DependencyManager.which(@name) != nil
        when :file 
          File.exists?(@name)
        else
          # Should not happen in production
          raise "Illegal dependency type #{@type}"
        end
    end
    
    @available
  end
  
  def to_s
    "#{@type} #{@name} is #{@relevance} for #{@source.join(' ').strip}"
  end
  
  attr_reader :name, :type, :source, :relevance, :reason, :version
  
  def relevance=(value)
    if ![:recommended, :essential].include?(value)
      raise "Illegal relevance #{value.to_s}"
    end
    
    @relevance = value
  end
end
