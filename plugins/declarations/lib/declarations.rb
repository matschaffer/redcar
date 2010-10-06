
require 'declarations/completion_source'
require 'declarations/file'
require 'declarations/parser'
require 'declarations/select_tag_dialog'
require 'declarations/commands'
require 'tempfile'

module Redcar
  class Declarations
    def self.menus
      Menu::Builder.build do
        sub_menu "Project" do
          item "Go to declaration", :command => Declarations::GoToTagCommand, :priority => 30
          item "Go to last location", :command => Declarations::GoBackCommand, :priority => 31
          item "Go to next location", :command => Declarations::GoForwardCommand, :priority => 32
        end
      end
    end

    def self.keymaps
      linwin = Keymap.build("main", [:linux, :windows]) do
        link "Ctrl+G",         Declarations::GoToTagCommand
        link "Ctrl+Alt+Left",  Declarations::GoBackCommand
        link "Ctrl+Alt+Right", Declarations::GoForwardCommand
      end

      osx = Keymap.build("main", :osx) do
        link "Cmd+G",         Declarations::GoToTagCommand
        link "Cmd+Alt+Left",  Declarations::GoBackCommand
        link "Cmd+Alt+Right", Declarations::GoForwardCommand
      end

      [linwin, osx]
    end

    def self.autocompletion_source_types
      [] #[Declarations::CompletionSource]
    end

    def self.file_path(project)
      ::File.join(project.config_dir, 'tags')
    end
    
    class ProjectRefresh < Task
      def initialize(project)
        @file_list   = project.file_list
        @project     = project
      end
      
      def description
        "#{@project.path}: reparse files for declarations"
      end
      
      def execute
        return if @project.remote?
        file = Declarations::File.new(Declarations.file_path(@project))
        file.update_files(@file_list)
        file.dump
        Declarations.clear_tags_for_path(file.path)
      end
    end
    
    def self.project_refresh_task_type
      ProjectRefresh
    end

    def self.tags_for_path(path)
      @tags_for_path ||= {}
      @tags_for_path[path] ||= begin
        tags = {}
        ::File.read(path).each_line do |line|
          key, file, *match = line.split("\t")
          if [key, file, match].all? { |el| !el.nil? && !el.empty? }
            tags[key] ||= []
            tags[key] << { :file => file, :match => match.join("\t").chomp }
          end
        end
        tags
      rescue Errno::ENOENT
        {}
      end
    end

    def self.match_kind(path, regex)
      Declarations::Parser.new.match_kind(path, regex)
    end

    def self.clear_tags_for_path(path)
      @tags_for_path ||= {}
      @tags_for_path.delete(path)
    end

    def self.current_location
      document = Redcar::EditView.focussed_edit_view.document
      [document.path, document.cursor_offset]
    end
    
    def self.go_to_location(location)
      path, offset = location
      Project::Manager.open_file(path)
      Redcar::EditView.focussed_edit_view.document.cursor_offset = offset
    end
    
    def self.go_back
      return unless location = @history.pop
      @future.push(current_location)
      go_to_location(location)
    end
    
    def self.go_forward
      return unless location = @future.pop
      @history.push(current_location)
      go_to_location(location)
    end

    def self.go_to_definition(match)
      (@history ||= []).push(current_location)
      @future = []
      path = match[:file]
      Project::Manager.open_file(path)
      regexp = Regexp.new(Regexp.escape(match[:match]))
      DocumentSearch::FindNextRegex.new(regexp, true).run
    end
  end
end
