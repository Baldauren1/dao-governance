const APP_STORAGE_KEY = "dao-governance-frontend-config";

const TOKEN_ABI = [
    "function balanceOf(address account) view returns (uint256)",
    "function getVotes(address account) view returns (uint256)",
    "function delegates(address account) view returns (address)",
    "function delegate(address delegatee) returns ()"
];

const GOVERNOR_ABI = [
    "event ProposalCreated(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,uint256 voteStart,uint256 voteEnd,string description)",
    "function state(uint256 proposalId) view returns (uint8)",
    "function proposalVotes(uint256 proposalId) view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)",
    "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
    "function hasVoted(uint256 proposalId, address account) view returns (bool)"
];

const PROPOSAL_STATES = [
    "Pending",
    "Active",
    "Canceled",
    "Defeated",
    "Succeeded",
    "Queued",
    "Expired",
    "Executed"
];

const els = {
    tokenAddress: document.getElementById("tokenAddress"),
    governorAddress: document.getElementById("governorAddress"),
    saveConfigButton: document.getElementById("saveConfigButton"),
    connectButton: document.getElementById("connectButton"),
    refreshButton: document.getElementById("refreshButton"),
    refreshProposalsButton: document.getElementById("refreshProposalsButton"),
    selfDelegateButton: document.getElementById("selfDelegateButton"),
    delegateButton: document.getElementById("delegateButton"),
    delegateAddress: document.getElementById("delegateAddress"),
    activeOnlyCheckbox: document.getElementById("activeOnlyCheckbox"),
    statusBox: document.getElementById("statusBox"),
    accountValue: document.getElementById("accountValue"),
    networkValue: document.getElementById("networkValue"),
    balanceValue: document.getElementById("balanceValue"),
    votesValue: document.getElementById("votesValue"),
    delegateValue: document.getElementById("delegateValue"),
    blockValue: document.getElementById("blockValue"),
    proposalList: document.getElementById("proposalList")
};

let provider = null;
let signer = null;
let currentAccount = null;

initialize();

function initialize() {
    loadSavedConfig();
    bindEvents();

    if (!window.ethereum) {
        setStatus("MetaMask was not detected. Install it first to use the dApp.", "error");
        toggleWalletButtons(true);
        return;
    }

    window.ethereum.on("accountsChanged", handleAccountsChanged);
    window.ethereum.on("chainChanged", () => window.location.reload());
}

function bindEvents() {
    els.saveConfigButton.addEventListener("click", saveConfig);
    els.connectButton.addEventListener("click", connectWallet);
    els.refreshButton.addEventListener("click", refreshAll);
    els.refreshProposalsButton.addEventListener("click", loadAndRenderProposals);
    els.selfDelegateButton.addEventListener("click", () => {
        if (!currentAccount) {
            setStatus("Connect MetaMask before self-delegating.", "error");
            return;
        }

        els.delegateAddress.value = currentAccount;
    });
    els.delegateButton.addEventListener("click", submitDelegation);
    els.activeOnlyCheckbox.addEventListener("change", loadAndRenderProposals);
}

function saveConfig() {
    const tokenAddress = els.tokenAddress.value.trim();
    const governorAddress = els.governorAddress.value.trim();

    if (!isValidAddress(tokenAddress) || !isValidAddress(governorAddress)) {
        setStatus("Both the token and governor addresses must be valid EVM addresses.", "error");
        return;
    }

    localStorage.setItem(
        APP_STORAGE_KEY,
        JSON.stringify({
            tokenAddress: ethers.getAddress(tokenAddress),
            governorAddress: ethers.getAddress(governorAddress)
        })
    );

    els.tokenAddress.value = ethers.getAddress(tokenAddress);
    els.governorAddress.value = ethers.getAddress(governorAddress);
    setStatus("Addresses saved locally. Refresh data to load the contracts.", "success");
}

function loadSavedConfig() {
    const raw = localStorage.getItem(APP_STORAGE_KEY);
    if (!raw) {
        return;
    }

    try {
        const config = JSON.parse(raw);
        els.tokenAddress.value = config.tokenAddress || "";
        els.governorAddress.value = config.governorAddress || "";
    } catch {
        localStorage.removeItem(APP_STORAGE_KEY);
    }
}

async function connectWallet() {
    if (!window.ethereum) {
        setStatus("MetaMask is required for this frontend.", "error");
        return;
    }

    try {
        provider = new ethers.BrowserProvider(window.ethereum);
        await provider.send("eth_requestAccounts", []);
        signer = await provider.getSigner();
        currentAccount = await signer.getAddress();

        setStatus(`Connected: ${shortAddress(currentAccount)}`, "success");
        await refreshAll();
    } catch (error) {
        setStatus(getReadableError(error), "error");
    }
}

async function handleAccountsChanged(accounts) {
    if (!accounts || accounts.length === 0) {
        currentAccount = null;
        signer = null;
        provider = null;
        resetWalletView();
        setStatus("Wallet disconnected.", "info");
        return;
    }

    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    currentAccount = accounts[0];

    await refreshAll();
}

async function refreshAll() {
    if (!currentAccount || !provider) {
        setStatus("Connect MetaMask first.", "error");
        return;
    }

    if (!hasValidConfig()) {
        setStatus("Enter valid token and governor addresses before refreshing.", "error");
        return;
    }

    toggleWalletButtons(true);

    try {
        await refreshWalletOverview();
        await loadAndRenderProposals();
        setStatus("Wallet data and proposals updated.", "success");
    } catch (error) {
        setStatus(getReadableError(error), "error");
    } finally {
        toggleWalletButtons(false);
    }
}

async function refreshWalletOverview() {
    const { token } = getContracts();
    const network = await provider.getNetwork();
    const currentBlock = await provider.getBlockNumber();

    const [balance, votes, delegate] = await Promise.all([
        token.balanceOf(currentAccount),
        token.getVotes(currentAccount),
        token.delegates(currentAccount)
    ]);

    els.accountValue.textContent = shortAddress(currentAccount);
    els.networkValue.textContent = `${network.name} (#${network.chainId.toString()})`;
    els.balanceValue.textContent = `${formatTokenAmount(balance)} GOV`;
    els.votesValue.textContent = `${formatTokenAmount(votes)} GOV`;
    els.delegateValue.textContent = delegate === ethers.ZeroAddress ? "Not delegated" : shortAddress(delegate);
    els.blockValue.textContent = currentBlock.toString();
}

async function submitDelegation() {
    if (!currentAccount || !provider) {
        setStatus("Connect MetaMask before delegating.", "error");
        return;
    }

    if (!hasValidConfig()) {
        setStatus("Save valid token and governor addresses first.", "error");
        return;
    }

    const delegatee = els.delegateAddress.value.trim();
    if (!isValidAddress(delegatee)) {
        setStatus("Enter a valid delegate address.", "error");
        return;
    }

    try {
        toggleWalletButtons(true);
        const { token } = getContracts();
        setStatus("Submitting delegation transaction...", "info");
        const tx = await token.delegate(ethers.getAddress(delegatee));
        setStatus(`Delegation sent: ${tx.hash}`, "info");
        await tx.wait();
        await refreshWalletOverview();
        setStatus(`Delegation confirmed: ${tx.hash}`, "success");
    } catch (error) {
        setStatus(getReadableError(error), "error");
    } finally {
        toggleWalletButtons(false);
    }
}

async function loadAndRenderProposals() {
    if (!provider || !currentAccount) {
        setStatus("Connect MetaMask before loading proposals.", "error");
        return;
    }

    if (!hasValidConfig()) {
        setStatus("Save valid contract addresses before loading proposals.", "error");
        return;
    }

    const { governor } = getContracts();

    try {
        els.proposalList.innerHTML = '<div class="empty">Loading proposals...</div>';

        const currentBlock = await provider.getBlockNumber();
        const events = await governor.queryFilter(
            governor.filters.ProposalCreated(),
            0,
            currentBlock
        );

        const proposals = await Promise.all(
            events.map(async (event) => {
                const proposalId = event.args.proposalId;
                const proposalStateId = Number(await governor.state(proposalId));
                const [againstVotes, forVotes, abstainVotes] = await governor.proposalVotes(proposalId);
                const hasVoted = await governor.hasVoted(proposalId, currentAccount);

                return {
                    id: proposalId.toString(),
                    proposer: event.args.proposer,
                    description: event.args.description || "No description",
                    voteStart: Number(event.args.voteStart),
                    voteEnd: Number(event.args.voteEnd),
                    againstVotes,
                    forVotes,
                    abstainVotes,
                    hasVoted,
                    stateId: proposalStateId,
                    stateLabel: PROPOSAL_STATES[proposalStateId] || "Unknown",
                    blockNumber: event.blockNumber
                };
            })
        );

        proposals.sort((left, right) => right.blockNumber - left.blockNumber);

        const filtered = els.activeOnlyCheckbox.checked
            ? proposals.filter((proposal) => proposal.stateLabel === "Active")
            : proposals;

        renderProposals(filtered, currentBlock);
    } catch (error) {
        els.proposalList.innerHTML = '<div class="empty">Unable to load proposals.</div>';
        throw error;
    }
}

function renderProposals(proposals, currentBlock) {
    els.proposalList.innerHTML = "";

    if (proposals.length === 0) {
        els.proposalList.innerHTML = '<div class="empty">No proposals match the current filter.</div>';
        return;
    }

    for (const proposal of proposals) {
        const card = document.createElement("article");
        card.className = "proposal-card";

        const head = document.createElement("div");
        head.className = "proposal-head";

        const headText = document.createElement("div");
        const id = document.createElement("div");
        id.className = "proposal-id";
        id.textContent = `Proposal ID: ${proposal.id}`;

        const description = document.createElement("h3");
        description.textContent = proposal.description;
        description.style.margin = "0.2rem 0 0";

        headText.append(id, description);

        const badge = document.createElement("div");
        badge.className = `badge ${badgeClassName(proposal.stateLabel)}`;
        badge.textContent = proposal.stateLabel;

        head.append(headText, badge);

        const helper = document.createElement("p");
        helper.className = "helper";
        helper.textContent = `Proposer: ${shortAddress(proposal.proposer)} | Vote window: blocks ${proposal.voteStart} - ${proposal.voteEnd}`;

        const meta = document.createElement("div");
        meta.className = "proposal-meta";
        meta.append(
            buildMetric("Current Block", currentBlock.toString()),
            buildMetric("You Voted", proposal.hasVoted ? "Yes" : "No"),
            buildMetric("Result", resultLabel(proposal.stateLabel))
        );

        const votes = document.createElement("div");
        votes.className = "vote-row";
        votes.append(
            buildMetric("Against", formatTokenAmount(proposal.againstVotes)),
            buildMetric("For", formatTokenAmount(proposal.forVotes)),
            buildMetric("Abstain", formatTokenAmount(proposal.abstainVotes))
        );

        card.append(head, helper, meta, votes);

        if (proposal.stateLabel === "Active") {
            const controls = document.createElement("div");
            controls.className = "proposal-controls";

            const supportSelect = document.createElement("select");
            supportSelect.innerHTML = [
                '<option value="0">Against</option>',
                '<option value="1" selected>For</option>',
                '<option value="2">Abstain</option>'
            ].join("");

            const voteButton = document.createElement("button");
            voteButton.className = "btn-primary";
            voteButton.textContent = proposal.hasVoted ? "Already Voted" : "Cast Vote";
            voteButton.disabled = proposal.hasVoted;
            voteButton.addEventListener("click", async () => {
                await submitVote(proposal.id, supportSelect.value);
            });

            const note = document.createElement("span");
            note.className = "helper";
            note.textContent = "Support values follow OpenZeppelin GovernorCountingSimple.";

            controls.append(supportSelect, voteButton, note);
            card.append(controls);
        }

        els.proposalList.append(card);
    }
}

async function submitVote(proposalId, supportValue) {
    if (!provider || !currentAccount) {
        setStatus("Connect MetaMask before voting.", "error");
        return;
    }

    try {
        toggleWalletButtons(true);
        const { governor } = getContracts();
        setStatus("Submitting vote transaction...", "info");
        const tx = await governor.castVote(proposalId, Number(supportValue));
        setStatus(`Vote sent: ${tx.hash}`, "info");
        await tx.wait();
        await refreshWalletOverview();
        await loadAndRenderProposals();
        setStatus(`Vote confirmed: ${tx.hash}`, "success");
    } catch (error) {
        setStatus(getReadableError(error), "error");
    } finally {
        toggleWalletButtons(false);
    }
}

function getContracts() {
    if (!provider || !signer) {
        throw new Error("Wallet is not connected.");
    }

    if (!hasValidConfig()) {
        throw new Error("Token and governor addresses are required.");
    }

    const tokenAddress = ethers.getAddress(els.tokenAddress.value.trim());
    const governorAddress = ethers.getAddress(els.governorAddress.value.trim());

    return {
        token: new ethers.Contract(tokenAddress, TOKEN_ABI, signer),
        governor: new ethers.Contract(governorAddress, GOVERNOR_ABI, signer)
    };
}

function hasValidConfig() {
    return isValidAddress(els.tokenAddress.value.trim()) && isValidAddress(els.governorAddress.value.trim());
}

function isValidAddress(value) {
    return Boolean(value) && ethers.isAddress(value);
}

function buildMetric(label, value) {
    const box = document.createElement("div");
    const title = document.createElement("span");
    const strong = document.createElement("strong");
    title.textContent = label;
    strong.textContent = value;
    box.append(title, strong);
    return box;
}

function badgeClassName(stateLabel) {
    return `badge-${stateLabel.toLowerCase()}`;
}

function resultLabel(stateLabel) {
    if (stateLabel === "Executed") return "Passed and executed";
    if (stateLabel === "Succeeded" || stateLabel === "Queued") return "Passed";
    if (stateLabel === "Defeated") return "Rejected";
    if (stateLabel === "Canceled") return "Canceled";
    if (stateLabel === "Expired") return "Expired";
    if (stateLabel === "Active") return "Voting in progress";
    return "Awaiting vote";
}

function resetWalletView() {
    els.accountValue.textContent = "Not connected";
    els.networkValue.textContent = "Unknown";
    els.balanceValue.textContent = "-";
    els.votesValue.textContent = "-";
    els.delegateValue.textContent = "-";
    els.blockValue.textContent = "-";
    els.proposalList.innerHTML = '<div class="empty">No proposals loaded yet.</div>';
}

function toggleWalletButtons(disabled) {
    els.connectButton.disabled = disabled;
    els.refreshButton.disabled = disabled;
    els.refreshProposalsButton.disabled = disabled;
    els.delegateButton.disabled = disabled;
    els.selfDelegateButton.disabled = disabled;
    els.saveConfigButton.disabled = disabled;
}

function formatTokenAmount(value) {
    const formatted = Number.parseFloat(ethers.formatUnits(value, 18));
    if (!Number.isFinite(formatted)) {
        return "0";
    }

    return formatted.toLocaleString(undefined, {
        maximumFractionDigits: 4
    });
}

function shortAddress(address) {
    if (!address || address === ethers.ZeroAddress) {
        return "0x0000...0000";
    }

    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function setStatus(message, kind = "info") {
    els.statusBox.textContent = message;
    els.statusBox.className = `status-box ${kind}`;
}

function getReadableError(error) {
    if (!error) {
        return "Unknown error";
    }

    return error.shortMessage
        || error.reason
        || error.info?.error?.message
        || error.message
        || "Transaction failed";
}
