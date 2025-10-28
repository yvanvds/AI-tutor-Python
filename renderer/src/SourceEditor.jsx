import Editor from '@monaco-editor/react';

export default function SourceEditor() {
  return (
    <div className="editor">
      <Editor
        defaultLanguage="python"
        defaultValue="// some comment"
      />  
    </div>
  );
}