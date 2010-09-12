
require File.dirname(__FILE__) + "/../vendor/session/lib/session"
Session.use_open4 = true

require 'runnables/command_output_controller'
require 'runnables/running_process_checker'
require 'runnables/output_processor'

module Redcar
  class Runnables
    TREE_TITLE = "Runnables"

    def self.run_process(path, command, title, output = "tab")
      if Runnables.storage['save_project_before_running'] == true
        Redcar.app.focussed_window.notebooks.each do |notebook|
          notebook.tabs.each do |tab|
            case tab
            when EditTab
              tab.edit_view.document.save!
            end
          end
        end
      end
      controller = CommandOutputController.new(path, command, title)
      if output == "none"
        controller.run        
      else
        if tab = previous_tab_for(command)
          tab.html_view.controller.run
          tab.focus
        else
          if output == "window"
            Redcar.app.new_window
          end
          tab = Redcar.app.focussed_window.new_tab(HtmlTab)
          tab.html_view.controller = controller
          tab.focus
        end        
      end
    end
    
    def self.previous_tab_for(command)
      Redcar.app.all_tabs.detect do |t|
        t.respond_to?(:html_view) &&
        t.html_view.controller.is_a?(CommandOutputController) &&
        t.html_view.controller.cmd == command
      end
    end

    def self.keymaps
      map = Keymap.build("main", [:osx, :linux, :windows]) do
        link "Ctrl+R", Runnables::RunEditTabCommand
      end
      [map, map]
    end

    def self.menus
      Menu::Builder.build do
        sub_menu "Project", :priority => 15 do
          group(:priority => 15) {
          separator
            item "Runnables", Runnables::ShowRunnables
            item "Run Tab",   Runnables::RunEditTabCommand
          }
        end
      end
    end
    
    class TreeMirror
      include Redcar::Tree::Mirror
      
      attr_accessor :last_loaded

      def initialize(project)
        @project = project
      end

      def runnable_file_paths
        @project.config_files("runnables/*.json")
      end

      def last_updated
        runnable_file_paths.map{ |p| File.mtime(p) }.max
      end

      def changed?
        !last_loaded || last_loaded < last_updated
      end

      def load
        groups = {}
        runnable_file_paths.each do |path|
          runnables = []
          name = File.basename(path,".json")
          json = File.read(path)
          this_runnables = JSON(json)["commands"]
          runnables += this_runnables || []
          groups[name.to_s] = runnables.to_a
        end

        if groups.any?
          groups.map do |name, runnables|
            RunnableGroup.new(name,runnables)
          end
        else
          [HelpItem.new]
        end
      end

      def title
        TREE_TITLE
      end

      def top
        load
      end
    end

    def self.storage
      @storage ||= begin
        storage = Plugin::Storage.new('runnables')
        storage.set_default('save_project_before_running', false)
        storage
      end
    end
    
    class RunnableGroup
      include Redcar::Tree::Mirror::NodeMirror
      
      def initialize(name,runnables)
        @name = name
        if runnables.any?
          @children = runnables.map do |runnable|
            Runnable.new(runnable["name"], runnable)
          end
        end
      end
      
      def leaf?
        false
      end
      
      def text
        @name
      end
      
      def icon
        :file
      end
      
      def children
        @children
      end
    end
    
    class HelpItem
      include Redcar::Tree::Mirror::NodeMirror
      
      def text
        "No runnables (HELP)"
      end
    end
    
    class Runnable
      include Redcar::Tree::Mirror::NodeMirror
      
      def initialize(name, info)
        @name = name
        @info = info
      end
      
      def text
        @name
      end
      
      def leaf?
        @info["command"]
      end
      
      def icon
        if leaf?
          File.dirname(__FILE__) + "/../icons/cog.png"
        else
          :directory
        end
      end
      
      def children
        []
      end
      
      def command
        @info["command"]
      end

      def out?
        @info["output"]
      end

      def output
        if out?
          @info["output"]
        else
          "tab"
        end
      end
    end
    
    class TreeController
      include Redcar::Tree::Controller
      
      def initialize(project)
        @project = project
      end
      
      def activated(tree, node)
        case node
        when Runnable
          Runnables.run_process(@project.home_dir, node.command, node.text, node.output)
        when HelpItem
          tab = Redcar.app.focussed_window.new_tab(HtmlTab)
          tab.go_to_location("http://wiki.github.com/danlucraft/redcar/users-guide-runnables")
          tab.title = "Runnables Help"
          tab.focus
        end
      end
    end
    
    class ShowRunnables < Redcar::Command
      def execute
        if tree = win.treebook.trees.detect {|tree| tree.tree_mirror.title == TREE_TITLE }
          tree.refresh
          win.treebook.focus_tree(tree)
        else
          project = Project::Manager.in_window(win)
          tree = Tree.new(
              TreeMirror.new(project),
              TreeController.new(project)
            )
          win.treebook.add_tree(tree)
        end
      end
    end
    
    class RunEditTabCommand < Redcar::EditTabCommand
      def matching_file_runners
        project = Project::Manager.in_window(win)
        runnable_file_paths = project.config_files("runnables/*.json")
        
        file_runners = runnable_file_paths.map do |file|
          json = File.read(file)
          JSON(json)["file_runners"] || []
        end.flatten

        file_runners.select do |file_runner|
          tab.edit_view.document.mirror.path =~ Regexp.new(file_runner["regex"])
        end
      end
      
      def run_file_mapping(file_mapping)        
        project = Project::Manager.in_window(win)
        command_schema = file_mapping["command"]
        output = file_mapping["output"] || "tab"
        path = tab.edit_view.document.mirror.path
        command = command_schema.gsub("__PATH__", path)
        Runnables.run_process(project.home_dir, command, "Running #{File.basename(path)}", output)
      end
      
      def execute
        mappings = matching_file_runners
        if mappings.size > 1
          builder = Menu::Builder.new do |m|
            mappings.each do |file_mapping|
              m.item(file_mapping["name"]||file_mapping["command"]) do |i|
                run_file_mapping(file_mapping)
              end
            end
          end
          Redcar.app.focussed_window.popup_menu_with_numbers(builder.menu)
        else
          run_file_mapping mappings.first
        end
      end
    end
  end
end
