import { PrimeReactProvider } from 'primereact/api';

import { Terminal } from 'primereact/terminal';
import SourceEditor from './SourceEditor.jsx';
import "primereact/resources/themes/saga-blue/theme.css";
import "primereact/resources/primereact.min.css";
import "primeicons/primeicons.css";
import "./App.css";

export default function App() {
  return <PrimeReactProvider>
    <Dashboard />
  </PrimeReactProvider>;
}

function Dashboard() {

  return (
    <div className="app-layout">
      <header className="app-header">AI Tutor for Python</header>

      <aside className="app-menu">
        <div>🏠</div>
        <div>📂</div>
        <div>⚙️</div>
      </aside>

      <main className="app-main">
        
        <SourceEditor/>

        <div className="console">
          <Terminal
            welcomeMessage="Welcome to PrimeReact"
            prompt="primereact $"
            pt={{
              root: 'bg-gray-900 text-white border-round',
              prompt: 'text-gray-400 mr-2',
              command: 'text-primary-300',
              response: 'text-primary-300'
            }}
          />
        </div>
      </main>

      <aside className="app-chat">AI Tutor panel</aside>
    </div>
  );

}

