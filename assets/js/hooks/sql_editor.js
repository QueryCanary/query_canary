import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { keymap } from "@codemirror/view"
import { sql, PostgreSQL, MySQL } from '@codemirror/lang-sql';
import { indentWithTab } from "@codemirror/commands";
import {
    acceptCompletion
  } from "@codemirror/autocomplete";

const SQLEditor = {
  mounted() {
    const editorContainer = this.el;
    const inputField = document.getElementById(`${this.el.id.replace('-editor', '')}-input`);
    const schemaScript = document.getElementById(`${this.el.id.replace('-editor', '')}-schema`);
    
    // Parse the schema from the script tag
    let schemaData = {};
    try {
      schemaData = JSON.parse(schemaScript.textContent);
    } catch (e) {
      console.error("Failed to parse SQL schema:", e);
    }

    // TODO: Move this to Elixir
    let dialect;
    switch(this.el.dataset.dialect?.toLowerCase()) {
      case 'mysql':
        dialect = MySQL;
        break;
      case 'postgres':
      case 'postgresql':
        dialect = PostgreSQL;
        break;
    }
     
    // Configure SQL extension with properly formatted schema
    const sqlLang = sql({
      dialect: dialect,
      schema: schemaData || []
    });

    
    // Create the editor
    const view = new EditorView({
      state: EditorState.create({
        doc: inputField.value,
        extensions: [
          basicSetup,
          keymap.of([{ key: "Tab", run: acceptCompletion }, indentWithTab]),
          sqlLang,
          EditorView.updateListener.of(update => {
            if (update.docChanged) {
                // Update the hidden input with the current editor content
                inputField.value = update.state.doc.toString();
                // Trigger an input event to notify LiveView of the change
                //   inputField.dispatchEvent(new Event('input', { bubbles: true }));
                inputField.dispatchEvent(new Event("change", { bubbles: true }));
            }
          }),
        ]
      }),
      parent: editorContainer
    });
    
    // Store the editor instance for cleanup and access
    this.editor = view;
  },
  
  updated() {
    // We could update the editor content here if needed
    // For now, we'll rely on the form to reset the editor
  },
  
  destroyed() {
    if (this.editor) {
      this.editor.destroy();
    }
  }
};

export default SQLEditor;