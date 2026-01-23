// Poker Client Application
const API_URL = 'http://localhost:8765';
const WS_URL = 'ws://localhost:8765/ws';

// State
let ws = null;
let accessToken = null;
let refreshToken = null;
let userId = null;
let username = null;
let userRole = null;
let currentTableId = null;
let gameState = null;

// DOM Elements
const authScreen = document.getElementById('auth-screen');
const lobbyScreen = document.getElementById('lobby-screen');
const gameScreen = document.getElementById('game-screen');

// ============ Utilities ============

function showScreen(screen) {
  [authScreen, lobbyScreen, gameScreen].forEach(s => s.classList.add('hidden'));
  screen.classList.remove('hidden');
}

function showError(elementId, message) {
  const el = document.getElementById(elementId);
  if (el) {
    el.textContent = message;
    setTimeout(() => el.textContent = '', 5000);
  }
}

function addChatMessage(author, text, isSystem = false) {
  const container = document.getElementById('chat-messages');
  const msg = document.createElement('div');
  msg.className = 'chat-message' + (isSystem ? ' system' : '');
  
  if (isSystem) {
    msg.textContent = text;
  } else {
    msg.innerHTML = `<div class="author">${author}</div><div class="text">${text}</div>`;
  }
  
  container.appendChild(msg);
  container.scrollTop = container.scrollHeight;
}

// ============ Auth ============

// Tab switching
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    
    const tabName = tab.dataset.tab;
    document.getElementById('login-form').classList.toggle('hidden', tabName !== 'login');
    document.getElementById('register-form').classList.toggle('hidden', tabName !== 'register');
  });
});

// Login
document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const usernameInput = document.getElementById('login-username').value;
  const password = document.getElementById('login-password').value;
  
  try {
    const res = await fetch(`${API_URL}/api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: usernameInput, password })
    });
    
    const data = await res.json();
    
    if (!res.ok) {
      throw new Error(data.detail || 'Login failed');
    }
    
    handleAuthSuccess(data);
  } catch (err) {
    showError('auth-error', err.message);
  }
});

// Register
document.getElementById('register-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const usernameInput = document.getElementById('register-username').value;
  const password = document.getElementById('register-password').value;
  
  try {
    const res = await fetch(`${API_URL}/api/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: usernameInput, password })
    });
    
    const data = await res.json();
    
    if (!res.ok) {
      throw new Error(data.detail || 'Registration failed');
    }
    
    handleAuthSuccess(data);
  } catch (err) {
    showError('auth-error', err.message);
  }
});

function handleAuthSuccess(data) {
  accessToken = data.access_token;
  refreshToken = data.refresh_token;
  userId = data.user_id;
  username = data.username;
  userRole = data.role || 'player';
  
  // Save to localStorage
  localStorage.setItem('accessToken', accessToken);
  localStorage.setItem('refreshToken', refreshToken);
  localStorage.setItem('userId', userId);
  localStorage.setItem('username', username);
  localStorage.setItem('userRole', userRole);
  
  document.getElementById('lobby-username').textContent = username;
  updateAdminUI();
  showScreen(lobbyScreen);
  loadTables();
}

function updateAdminUI() {
  const isAdmin = userRole === 'admin';
  const roleBadge = document.getElementById('role-badge');
  const createBtn = document.getElementById('create-table-btn');
  
  if (isAdmin) {
    roleBadge.classList.remove('hidden');
    createBtn.classList.remove('hidden');
  } else {
    roleBadge.classList.add('hidden');
    createBtn.classList.add('hidden');
  }
}

// Logout
document.getElementById('logout-btn').addEventListener('click', () => {
  accessToken = null;
  refreshToken = null;
  userId = null;
  username = null;
  localStorage.clear();
  if (ws) ws.close();
  showScreen(authScreen);
});

// Check for existing session
function checkExistingSession() {
  const savedToken = localStorage.getItem('accessToken');
  const savedRefresh = localStorage.getItem('refreshToken');
  const savedUserId = localStorage.getItem('userId');
  const savedUsername = localStorage.getItem('username');
  const savedRole = localStorage.getItem('userRole');
  
  if (savedToken && savedRefresh && savedUserId && savedUsername) {
    accessToken = savedToken;
    refreshToken = savedRefresh;
    userId = savedUserId;
    username = savedUsername;
    userRole = savedRole || 'player';
    document.getElementById('lobby-username').textContent = username;
    updateAdminUI();
    showScreen(lobbyScreen);
    loadTables();
  }
}

// ============ Lobby ============

async function loadTables() {
  const container = document.getElementById('tables-list');
  container.innerHTML = '<p class="loading">Loading tables...</p>';
  
  try {
    const res = await fetch(`${API_URL}/api/tables`);
    const data = await res.json();
    
    const isAdmin = userRole === 'admin';
    
    if (data.tables.length === 0) {
      container.innerHTML = isAdmin 
        ? '<p class="loading">No tables yet. Create one to get started!</p>'
        : '<p class="loading">No tables available. Ask an admin to create one.</p>';
      return;
    }
    
    container.innerHTML = data.tables.map(table => `
      <div class="table-item">
        <div class="table-item-info">
          <h4>${table.table_id}</h4>
          <span>${table.players}/${table.max_players} players • Blinds: $${table.small_blind}/$${table.big_blind} • ${table.state}</span>
        </div>
        <div class="table-item-actions">
          <button onclick="joinTable('${table.table_id}')">Join</button>
          ${isAdmin ? `<button class="delete-btn" onclick="deleteTable('${table.table_id}')">Delete</button>` : ''}
        </div>
      </div>
    `).join('');
  } catch (err) {
    container.innerHTML = '<p class="loading">Failed to load tables</p>';
  }
}

document.getElementById('refresh-tables').addEventListener('click', loadTables);

// ============ Admin: Create/Delete Tables ============

document.getElementById('create-table-btn').addEventListener('click', () => {
  document.getElementById('create-table-modal').classList.remove('hidden');
  document.getElementById('new-table-id').focus();
});

document.getElementById('cancel-create-table').addEventListener('click', () => {
  document.getElementById('create-table-modal').classList.add('hidden');
  document.getElementById('create-table-form').reset();
  document.getElementById('create-table-error').textContent = '';
});

// Close modal when clicking outside
document.getElementById('create-table-modal').addEventListener('click', (e) => {
  if (e.target.id === 'create-table-modal') {
    document.getElementById('create-table-modal').classList.add('hidden');
    document.getElementById('create-table-form').reset();
    document.getElementById('create-table-error').textContent = '';
  }
});

document.getElementById('create-table-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  
  const tableId = document.getElementById('new-table-id').value.trim();
  const smallBlind = parseInt(document.getElementById('new-small-blind').value);
  const bigBlind = parseInt(document.getElementById('new-big-blind').value);
  const minPlayers = parseInt(document.getElementById('new-min-players').value);
  const maxPlayers = parseInt(document.getElementById('new-max-players').value);
  
  try {
    const res = await fetch(`${API_URL}/api/tables`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        table_id: tableId,
        small_blind: smallBlind,
        big_blind: bigBlind,
        min_players: minPlayers,
        max_players: maxPlayers,
      }),
    });
    
    const data = await res.json();
    
    if (!res.ok) {
      throw new Error(data.detail || 'Failed to create table');
    }
    
    // Success - close modal and refresh
    document.getElementById('create-table-modal').classList.add('hidden');
    document.getElementById('create-table-form').reset();
    loadTables();
  } catch (err) {
    document.getElementById('create-table-error').textContent = err.message;
  }
});

async function deleteTable(tableId) {
  if (!confirm(`Delete table "${tableId}"? Players will be removed.`)) {
    return;
  }
  
  try {
    const res = await fetch(`${API_URL}/api/tables/${encodeURIComponent(tableId)}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    });
    
    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.detail || 'Failed to delete table');
    }
    
    loadTables();
  } catch (err) {
    alert('Error: ' + err.message);
  }
}

window.deleteTable = deleteTable;

// ============ WebSocket ============

function connectWebSocket() {
  return new Promise((resolve, reject) => {
    ws = new WebSocket(WS_URL);
    
    ws.onopen = () => {
      console.log('WebSocket connected');
      // Authenticate
      ws.send(JSON.stringify({ type: 'auth', token: accessToken }));
    };
    
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      handleMessage(msg);
      
      if (msg.type === 'authenticated') {
        resolve();
      }
    };
    
    ws.onerror = (err) => {
      console.error('WebSocket error:', err);
      reject(err);
    };
    
    ws.onclose = () => {
      console.log('WebSocket closed');
      if (currentTableId) {
        addChatMessage(null, 'Connection lost. Reconnecting...', true);
        setTimeout(() => {
          if (currentTableId) {
            connectAndJoin(currentTableId);
          }
        }, 2000);
      }
    };
  });
}

function handleMessage(msg) {
  console.log('Received:', msg.type, msg);
  
  switch (msg.type) {
    case 'authenticated':
      addChatMessage(null, 'Connected to server', true);
      break;
      
    case 'error':
      addChatMessage(null, `Error: ${msg.message}`, true);
      if (msg.message.includes('not found') || msg.message.includes('does not exist')) {
        leaveTable();
      }
      break;
      
    case 'player_joined':
      addChatMessage(null, `${msg.username} joined the table`, true);
      break;
      
    case 'player_left':
      addChatMessage(null, `${msg.username} left the table`, true);
      break;
      
    case 'game_state':
      gameState = msg;
      renderGameState(msg);
      break;
      
    case 'player_action':
      const actionText = msg.amount > 0 ? `${msg.action} $${msg.amount}` : msg.action;
      addChatMessage(null, `${msg.username}: ${actionText}`, true);
      break;
      
    case 'hand_result':
      const winners = msg.winners.map(w => `${w.username} wins $${w.amount}`).join(', ');
      addChatMessage(null, `Hand complete: ${winners}`, true);
      break;
      
    case 'chat':
      addChatMessage(msg.username, msg.message);
      break;
      
    case 'chips_updated':
      addChatMessage(null, `${msg.player}: ${msg.action} $${msg.amount} (now $${msg.chips})`, true);
      // Update local game state if we have it
      if (gameState && gameState.players) {
        const player = gameState.players.find(p => p.username === msg.player);
        if (player) player.chips = msg.chips;
        renderGameState(gameState);
      }
      break;
      
    case 'hand_started':
      addChatMessage(null, `Hand #${msg.hand_number} started`, true);
      break;
      
    case 'state_changed':
      addChatMessage(null, `Stage: ${msg.state}`, true);
      break;
      
    case 'tables_list':
      // Could update lobby if needed
      break;
      
    default:
      console.log('Unhandled message type:', msg.type);
  }
}

// ============ Game ============

async function joinTable(tableId) {
  await connectAndJoin(tableId);
}

async function connectAndJoin(tableId) {
  try {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      await connectWebSocket();
    }
    
    ws.send(JSON.stringify({ type: 'join_table', table_id: tableId }));
    currentTableId = tableId;
    document.getElementById('table-name').textContent = `Table: ${tableId}`;
    showScreen(gameScreen);
    document.getElementById('chat-messages').innerHTML = '';
    addChatMessage(null, `Joining table ${tableId}...`, true);
  } catch (err) {
    console.error('Failed to connect:', err);
    showError('auth-error', 'Failed to connect to server');
  }
}

window.joinTable = joinTable;

document.getElementById('leave-table-btn').addEventListener('click', leaveTable);

function leaveTable() {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'leave_table' }));
  }
  currentTableId = null;
  gameState = null;
  showScreen(lobbyScreen);
  loadTables();
}

// ============ Rendering ============

function renderGameState(state) {
  // Update header
  document.getElementById('hand-number').textContent = `Hand #${state.hand_number || 0}`;
  document.getElementById('game-state').textContent = state.state;
  
  // Update pot
  document.getElementById('pot').textContent = `Pot: $${state.pot || 0}`;
  
  // Render community cards
  renderCommunityCards(state.community_cards || []);
  
  // Render players
  renderPlayers(state.players || [], state.current_player, state.dealer_seat);
  
  // Update action buttons
  updateActionButtons(state);
  
  // Show/hide admin controls
  const adminControls = document.getElementById('admin-controls');
  if (userRole === 'admin') {
    adminControls.classList.remove('hidden');
  } else {
    adminControls.classList.add('hidden');
  }
}

function renderCommunityCards(cards) {
  const container = document.getElementById('community-cards');
  
  // Always show 5 card slots
  let html = '';
  for (let i = 0; i < 5; i++) {
    if (i < cards.length) {
      html += renderCard(cards[i]);
    } else {
      html += '<div class="card empty"></div>';
    }
  }
  container.innerHTML = html;
}

function renderCard(cardStr) {
  if (!cardStr) return '<div class="card hidden-card">?</div>';
  
  // Parse card string like "Ah" or "10d"
  const suitMap = { 'h': '♥', 'd': '♦', 'c': '♣', 's': '♠' };
  const suitClassMap = { 'h': 'hearts', 'd': 'diamonds', 'c': 'clubs', 's': 'spades' };
  
  const suit = cardStr.slice(-1).toLowerCase();
  const rank = cardStr.slice(0, -1);
  
  return `<div class="card ${suitClassMap[suit] || ''}">${rank}${suitMap[suit] || suit}</div>`;
}

function renderPlayers(players, currentPlayerId, dealerSeat) {
  // Clear all seats
  document.querySelectorAll('.seat').forEach(seat => {
    seat.innerHTML = '';
    seat.classList.add('empty');
  });
  
  players.forEach(player => {
    const seat = document.querySelector(`.seat-${player.seat}`);
    if (!seat) return;
    
    seat.classList.remove('empty');
    
    const isCurrent = player.user_id === currentPlayerId;
    const isYou = player.user_id === userId;
    const isFolded = player.is_folded;
    const isDealer = player.seat === dealerSeat;
    
    let classes = 'player-box';
    if (isCurrent) classes += ' is-current';
    if (isYou) classes += ' is-you';
    if (isFolded) classes += ' is-folded';
    
    let cardsHtml = '';
    // Server sends hole_cards for your own cards
    const cards = player.hole_cards || player.cards;
    if (cards && cards.length > 0) {
      cardsHtml = `
        <div class="player-cards">
          ${cards.map(c => renderCard(c)).join('')}
        </div>
      `;
    } else if (!isFolded && player.has_cards) {
      cardsHtml = `
        <div class="player-cards">
          <div class="card hidden-card">?</div>
          <div class="card hidden-card">?</div>
        </div>
      `;
    }
    
    seat.innerHTML = `
      <div class="${classes}">
        ${isDealer ? '<div class="dealer-chip">D</div>' : ''}
        <div class="player-name">${player.username}${isYou ? ' (you)' : ''}</div>
        <div class="player-chips">$${player.chips}</div>
        ${player.bet > 0 ? `<div class="player-bet">Bet: $${player.bet}</div>` : ''}
        ${cardsHtml}
      </div>
    `;
  });
}

function updateActionButtons(state) {
  const validActions = state.valid_actions || [];
  const isMyTurn = state.current_player === userId;
  
  const foldBtn = document.getElementById('btn-fold');
  const checkBtn = document.getElementById('btn-check');
  const callBtn = document.getElementById('btn-call');
  const raiseBtn = document.getElementById('btn-raise');
  const allinBtn = document.getElementById('btn-allin');
  const raiseControls = document.getElementById('raise-controls');
  
  // Disable all by default
  [foldBtn, checkBtn, callBtn, raiseBtn, allinBtn].forEach(btn => btn.disabled = true);
  raiseControls.classList.add('hidden');
  
  if (!isMyTurn) return;
  
  if (validActions.includes('fold')) foldBtn.disabled = false;
  if (validActions.includes('check')) checkBtn.disabled = false;
  if (validActions.includes('call')) {
    callBtn.disabled = false;
    callBtn.textContent = `Call $${state.call_amount || 0}`;
  }
  if (validActions.includes('raise') || validActions.includes('bet')) {
    raiseBtn.disabled = false;
    raiseBtn.textContent = validActions.includes('bet') ? 'Bet' : 'Raise';
  }
  if (validActions.includes('all_in')) allinBtn.disabled = false;
  
  // Set up raise slider
  const myPlayer = state.players.find(p => p.user_id === userId);
  if (myPlayer) {
    const minRaise = state.min_raise || state.big_blind || 2;
    const maxRaise = myPlayer.chips;
    
    document.getElementById('raise-amount').min = minRaise;
    document.getElementById('raise-amount').max = maxRaise;
    document.getElementById('raise-amount').value = minRaise;
    document.getElementById('raise-value').min = minRaise;
    document.getElementById('raise-value').max = maxRaise;
    document.getElementById('raise-value').value = minRaise;
    document.getElementById('btn-raise-confirm').textContent = `Raise $${minRaise}`;
  }
}

// ============ Action Buttons ============

document.getElementById('btn-fold').addEventListener('click', () => sendAction('fold'));
document.getElementById('btn-check').addEventListener('click', () => sendAction('check'));
document.getElementById('btn-call').addEventListener('click', () => sendAction('call'));
document.getElementById('btn-allin').addEventListener('click', () => sendAction('all_in'));

document.getElementById('btn-raise').addEventListener('click', () => {
  document.getElementById('raise-controls').classList.toggle('hidden');
});

document.getElementById('raise-amount').addEventListener('input', (e) => {
  document.getElementById('raise-value').value = e.target.value;
  document.getElementById('btn-raise-confirm').textContent = `Raise $${e.target.value}`;
});

document.getElementById('raise-value').addEventListener('input', (e) => {
  document.getElementById('raise-amount').value = e.target.value;
  document.getElementById('btn-raise-confirm').textContent = `Raise $${e.target.value}`;
});

document.getElementById('btn-raise-confirm').addEventListener('click', () => {
  const amount = parseInt(document.getElementById('raise-value').value);
  sendAction('raise', amount);
  document.getElementById('raise-controls').classList.add('hidden');
});

function sendAction(action, amount = 0) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'action', action, amount }));
  }
}

// ============ Chat ============

document.getElementById('chat-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const input = document.getElementById('chat-input');
  const message = input.value.trim();
  
  if (message && ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'chat', message }));
    input.value = '';
  }
});

// ============ Admin Controls ============

// Start Hand button
document.getElementById('btn-start-hand').addEventListener('click', () => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'start_game' }));
    addChatMessage(null, 'Starting hand...', true);
  }
});

// Give Chips button - open modal
document.getElementById('btn-give-chips').addEventListener('click', () => {
  openGiveChipsModal();
});

function openGiveChipsModal() {
  const modal = document.getElementById('give-chips-modal');
  const select = document.getElementById('chips-player');
  
  // Populate player dropdown from current game state
  select.innerHTML = '<option value="">Select player...</option>';
  if (gameState && gameState.players) {
    gameState.players.forEach(p => {
      select.innerHTML += `<option value="${p.username}">${p.username} ($${p.chips})</option>`;
    });
  }
  
  document.getElementById('chips-amount').value = 500;
  document.getElementById('give-chips-error').textContent = '';
  document.getElementById('give-chips-success').textContent = '';
  modal.classList.remove('hidden');
}

document.getElementById('cancel-give-chips').addEventListener('click', () => {
  document.getElementById('give-chips-modal').classList.add('hidden');
});

// Close modal when clicking outside
document.getElementById('give-chips-modal').addEventListener('click', (e) => {
  if (e.target.id === 'give-chips-modal') {
    document.getElementById('give-chips-modal').classList.add('hidden');
  }
});

// Chip preset buttons
document.querySelectorAll('.chip-preset').forEach(btn => {
  btn.addEventListener('click', () => {
    const amount = parseInt(btn.dataset.amount);
    const input = document.getElementById('chips-amount');
    input.value = Math.abs(amount);
    
    // If negative, trigger take chips
    if (amount < 0) {
      document.getElementById('take-chips-btn').click();
    } else {
      document.getElementById('give-chips-form').requestSubmit();
    }
  });
});

// Give chips form submit
document.getElementById('give-chips-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const player = document.getElementById('chips-player').value;
  const amount = parseInt(document.getElementById('chips-amount').value);
  
  if (!player) {
    document.getElementById('give-chips-error').textContent = 'Select a player';
    return;
  }
  if (!amount || amount <= 0) {
    document.getElementById('give-chips-error').textContent = 'Enter a valid amount';
    return;
  }
  
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'give_chips', player, amount }));
    document.getElementById('give-chips-error').textContent = '';
    document.getElementById('give-chips-success').textContent = `Gave $${amount} to ${player}`;
    
    // Update dropdown after a moment
    setTimeout(() => {
      if (gameState && gameState.players) {
        const select = document.getElementById('chips-player');
        const currentVal = select.value;
        select.innerHTML = '<option value="">Select player...</option>';
        gameState.players.forEach(p => {
          select.innerHTML += `<option value="${p.username}">${p.username} ($${p.chips})</option>`;
        });
        select.value = currentVal;
      }
    }, 500);
  }
});

// Take chips button
document.getElementById('take-chips-btn').addEventListener('click', () => {
  const player = document.getElementById('chips-player').value;
  const amount = parseInt(document.getElementById('chips-amount').value);
  
  if (!player) {
    document.getElementById('give-chips-error').textContent = 'Select a player';
    return;
  }
  if (!amount || amount <= 0) {
    document.getElementById('give-chips-error').textContent = 'Enter a valid amount';
    return;
  }
  
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'take_chips', player, amount }));
    document.getElementById('give-chips-error').textContent = '';
    document.getElementById('give-chips-success').textContent = `Took $${amount} from ${player}`;
  }
});

// ============ Init ============

checkExistingSession();
