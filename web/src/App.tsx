import { useEffect, useState } from 'react'
import { ethers } from 'ethers'
import { toast } from 'react-hot-toast'
import TokenReleaseDelayABI from '../contracts/TokenReleaseDelay.json'

// Update this to your deployed proxy contract address
const CONTRACT_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3'

declare global {
  interface Window {
    ethereum?: any
  }
}

function App() {
  const [account, setAccount] = useState<string>('')
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null)
  const [releases, setReleases] = useState<any[]>([])
  const [claimableAmount, setClaimableAmount] = useState<string>('0')

  useEffect(() => {
    if (window.ethereum) {
      const provider = new ethers.BrowserProvider(window.ethereum)
      setProvider(provider)

      // Listen for account changes
      window.ethereum.on('accountsChanged', (accounts: string[]) => {
        if (accounts.length > 0) {
          setAccount(accounts[0])
          loadUserData(accounts[0])
        } else {
          setAccount('')
          setReleases([])
          setClaimableAmount('0')
        }
      })
    }
  }, [])

  const connectWallet = async () => {
    try {
      if (!provider) {
        toast.error('Please install MetaMask')
        return
      }
      const accounts = await provider.send("eth_requestAccounts", [])
      setAccount(accounts[0])
      loadUserData(accounts[0])
    } catch (error) {
      console.error('Error connecting wallet:', error)
      toast.error('Failed to connect wallet')
    }
  }

  const loadUserData = async (userAddress: string) => {
    try {
      if (!provider) return
      const contract = new ethers.Contract(CONTRACT_ADDRESS, TokenReleaseDelayABI, provider)
      
      // Load user plans
      const userPlans = []
      let index = 0
      while (true) {
        try {
          const release = await contract.userPlans(userAddress, index)
          userPlans.push({
            index,
            startTime: release[0],
            amount: release[1],
            delayCompensationAmount: release[2],
            claimed: release[3]
          })
          index++
        } catch (error) {
          break
        }
      }
      setReleases(userPlans)

      // Load claimable amount
      const amount = await contract.getClaimableAmount(userAddress)
      setClaimableAmount(ethers.formatEther(amount))
    } catch (error) {
      console.error('Error loading user data:', error)
      toast.error('Failed to load user data')
    }
  }

  const claimToken = async (index: number) => {
    try {
      if (!provider) return
      const signer = await provider.getSigner()
      const contract = new ethers.Contract(CONTRACT_ADDRESS, TokenReleaseDelayABI, signer)
      
      toast.loading('Claiming tokens...')
      const tx = await contract.claimIndex(index)
      await tx.wait()
      
      toast.success('Successfully claimed tokens')
      loadUserData(account)
    } catch (error) {
      console.error('Error claiming tokens:', error)
      toast.error('Failed to claim tokens')
    }
  }

  const claimAll = async () => {
    try {
      if (!provider) return
      const signer = await provider.getSigner()
      const contract = new ethers.Contract(CONTRACT_ADDRESS, TokenReleaseDelayABI, signer)
      
      toast.loading('Claiming all tokens...')
      const tx = await contract.claimAll()
      await tx.wait()
      
      toast.success('Successfully claimed all tokens')
      loadUserData(account)
    } catch (error) {
      console.error('Error claiming all tokens:', error)
      toast.error('Failed to claim all tokens')
    }
  }

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-bold">Token Release Dashboard</h1>
        <button
          onClick={connectWallet}
          className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600 transition-colors"
        >
          {account ? `${account.slice(0, 6)}...${account.slice(-4)}` : 'Connect Wallet'}
        </button>
      </div>

      {account && (
        <>
          <div className="bg-white rounded-lg shadow p-6 mb-6">
            <h2 className="text-xl font-semibold mb-2">Claimable Amount</h2>
            <p className="text-2xl">{claimableAmount} Tokens</p>
            {Number(claimableAmount) > 0 && (
              <button
                onClick={claimAll}
                className="mt-4 bg-green-500 text-white px-4 py-2 rounded hover:bg-green-600 transition-colors"
              >
                Claim All
              </button>
            )}
          </div>

          <div className="bg-white rounded-lg shadow overflow-hidden">
            <h2 className="text-xl font-semibold p-6 border-b">Release Plans</h2>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Index</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Start Time</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Amount</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Delay Compensation</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {releases.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-6 py-4 text-center text-gray-500">
                        No release plans found
                      </td>
                    </tr>
                  ) : (
                    releases.map((release) => (
                      <tr key={release.index}>
                        <td className="px-6 py-4 whitespace-nowrap">{release.index}</td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {new Date(Number(release.startTime) * 1000).toLocaleString()}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {ethers.formatEther(release.amount)}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {ethers.formatEther(release.delayCompensationAmount)}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {release.claimed ? (
                            <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800">
                              Claimed
                            </span>
                          ) : (
                            <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800">
                              Pending
                            </span>
                          )}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {!release.claimed && Number(release.startTime) * 1000 <= Date.now() && (
                            <button
                              onClick={() => claimToken(release.index)}
                              className="text-blue-600 hover:text-blue-900 transition-colors"
                            >
                              Claim
                            </button>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

export default App