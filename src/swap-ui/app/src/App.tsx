import SwapInterface from './components/SwapInterface'
import './App.css'

function App() {
  return (
    <div className="App">
      <header className="app-header">
        <div className="container mx-auto px-4 py-6">
          <h1 className="text-2xl font-bold text-white">THORChain Swap</h1>
        </div>
      </header>
      <main className="flex-1 flex items-center justify-center p-4">
        <SwapInterface />
      </main>
    </div>
  )
}

export default App
