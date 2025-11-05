# Button Game Mini App - TODO

## Overview
Super minimal frontend mini-app for the Based Button game. Displays current round state, allows players to press the button, and shows game progress.

## Features to Implement

### 1. Header Section
- **Title**: "Based Button"
- **Brief Description**: One-liner explaining the last-deposit-wins game mechanics

### 2. Last Player Display
- Show last person who played (address)
- Lookup Farcaster ID by address (using Farcaster API/verification)
- Display as: "Last played by: @farcaster_username" or fallback to truncated address

### 3. Pot Amount
- Display current pot balance from `getRoundState(roundId).potBalance`
- Format as currency (USDC with proper decimals)
- Large, prominent display

### 4. Play Button
- "Play" button (primary CTA)
- Caption below showing cost: "Cost: X USDC" (from `getCurrentPrice(roundId)`)
- On click: check approval, approve if needed, then call `play(roundId, maxPrice)`
- Disable during transaction processing

### 5. Round Timer
- Countdown display: "Time remaining: X minutes Y seconds"
- Use `getTimeRemaining(roundId)` and poll every second
- Show "Round expired" when time is 0

### 6. Progress Bar
- Visual indicator of round progress
- Calculate: `(currentTime - startTime) / roundDuration * 100`
- Use `getRoundState(roundId).startTime` and `getRoundConfig(roundId).roundDuration`

### 7. Game Rules
- Bullet points explaining:
  - Last person to press before timer expires wins the pot
  - Each play extends the timer by the round duration
  - Play price is fixed per round
  - Winner is paid automatically when round finalizes

### 8. Fee Breakdown
- Text showing: "X% of funds go into the pot, Y% goes to dev"
- Calculate from `getRoundConfig(roundId).feeBps`
- Display: `(10000 - feeBps) / 100`% pot, `feeBps / 100`% dev

## Technical Implementation Notes

### Data Fetching
- Use `getLatestRoundId()` to get current round
- Fetch round state/config on mount and after each play
- Poll `getTimeRemaining()` every second for countdown
- Cache schedule data (no need to refetch frequently)

### Wallet Integration
- Connect wallet (via wagmi/viem or similar)
- Check USDC approval before play button click
- Show approval transaction if needed
- Handle transaction states (pending, success, error)

### Farcaster Integration
- Lookup Farcaster username by address
- Use Farcaster API or verification endpoint
- Cache lookups to avoid rate limits
- Fallback gracefully if lookup fails

### UI/UX Considerations
- Minimal, clean design
- Responsive for mobile
- Clear visual hierarchy (pot amount, play button most prominent)
- Loading states for transactions
- Error handling with user-friendly messages
