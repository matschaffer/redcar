module Redcar
  class Declarations
    class DeclarationCommand < EditTabCommand
      def execute
        if Project::Manager.focussed_project.remote?
          Application::Dialog.message_box("Go to declaration doesn't work in remote projects yet :(")
          return
        end
      end
    end
    
    class GoToTagCommand < DeclarationCommand

      def execute
        super

        if doc.selection?
          handle_tag(doc.selected_text)
        else
          range = doc.current_word_range
          handle_tag(doc.get_slice(range.first, range.last))
        end
      end

      def handle_tag(token = '')
        tags_path = Declarations.file_path(Project::Manager.focussed_project)
        unless ::File.exist?(tags_path)
          Application::Dialog.message_box("The declarations file 'tags' has not been generated yet.")
          return
        end
        matches = find_tag(tags_path, token)
        case matches.size
        when 0
          Application::Dialog.message_box("There is no declaration for '#{token}' in the 'tags' file.")
        when 1
          Redcar::Declarations.go_to_definition(matches.first)
        else
          open_select_tag_dialog(matches)
        end
      end

      def find_tag(tags_path, tag)
        Declarations.tags_for_path(tags_path)[tag] || []
      end

      def open_select_tag_dialog(matches)
        Declarations::SelectTagDialog.new(matches).open
      end
    end
    
    class GoBackCommand < DeclarationCommand
      def execute
        super
        Declarations.go_back
      end
    end
    
    class GoForwardCommand < DeclarationCommand
      def execute
        super
        Declarations.go_forward        
      end
    end
  end
end
