

import {basicSetup, EditorView} from "codemirror";
import {PostgreSQL, sql} from "@codemirror/lang-sql";


export default {
    mounted() {
        const element = this.el;

        let view = new EditorView({
            doc: element.value,
            extensions: [
                basicSetup,
                sql({
                    dialect: PostgreSQL
                }),
                EditorView.updateListener.of(function(e) {
                    if (e.docChanged) {
                        element.value = e.state.doc.toString();
                        element.dispatchEvent(new Event("change", { bubbles: true }));
                    } 
                })
            ],
            parent: document.querySelector("#code-codemirror"),
        });

        // element.parentNode.insertBefore(view.dom, element);
        // element.style.display = "none";
    }

}

// function editorFromTextArea(textarea, extensions) {
//     let view = new EditorView({doc: textarea.value, extensions})
//     textarea.parentNode.insertBefore(view.dom, textarea)
//     textarea.style.display = "none"
//     if (textarea.form) textarea.form.addEventListener("submit", () => {
//       textarea.value = view.state.doc.toString()
//     })
//     return view
//   }
  