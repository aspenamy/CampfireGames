-------------------------------------------------------------------------------
-- Campfire Games: how to play
--
-- Shown by the ? button in a game's header. Plain and short.
-------------------------------------------------------------------------------

local _, ns = ...

ns.HELP = {
  sudoku = "Fill the grid so every row, column and 3x3 box has the numbers 1 to 9 once each.\n\n"
    .. "Click a cell, then a number. With a cell picked you can also type 1-9, use the arrow keys, and press Esc to let go.\n\n"
    .. "Notes pencils in small numbers (Shift+number does the same). Right-click a cell to clear it.\n\n"
    .. "Daily gives everyone the same puzzle each day, and keeps your regular puzzle waiting.",

  gems = "Swap two gems next to each other to line up three or more of a kind.\n\n"
    .. "Four in a line makes an ember gem that clears the gems around it. Five makes a prism: swap it with any gem to clear every gem of that kind.\n\n"
    .. "Relaxed never ends. 30 Moves is a race for the best score.",

  fireflies = "Press on a light and drag through its neighbors of the same color, up, down, left or right. The firefly follows your line. Link 2 or more and let go to catch them, or drag back to undo a link.\n\n"
    .. "Link 5 and the last light stays as a beacon: catch it later to clear its whole row and column. Link 8 and it becomes a dewdrop, which counts as any color.\n\n"
    .. "End your line on a light already in it to make a loop. A loop catches every light of that color, and lights inside the loop burst like lanterns. Linking 10 does the same.\n\n"
    .. "Catch 6 or more in a move, twice in a row, for a glow streak that multiplies your score.\n\n"
    .. "Levels: reach the target score by your last move to pass. Fill the goals under the board for big score bonuses. Later levels bring dewdrops, twin lights, cobwebs and seeds, each explained when it first appears. 30 Moves is for a high score, and Relaxed has no limit.",

  solitaire = "Build each suit up from Ace to King on the four piles at the top right.\n\n"
    .. "On the table, stack cards down in alternating colors. Only a King can go in an empty space.\n\n"
    .. "Drag a card to where it goes, or click it and then click the spot. Click a card twice to send it to the best spot, or right-click to send it up to its suit. Click the deck to draw.",

  digsite = "Dig every safe square without setting off a trap. Your first dig is always safe.\n\n"
    .. "A number tells you how many traps touch that square, counting diagonals.\n\n"
    .. "Right-click to plant a flag where you think a trap is. Clicking a number that already has enough flags around it digs the rest.",

  slider = "Slide the tiles back into the picture. Pictures come from the zone maps of Azeroth.\n\n"
    .. "Click a tile next to the gap to slide it in. Click a tile further along the same row or column and the whole run slides. The small picture in the corner shows the goal, and Peek shows it over the board.\n\n"
    .. "Numbers adds a small number to each tile. Every tile moved counts as a move, and the clock starts at your first move. New puzzle picks a different picture.",

  lanterns = "Light every lantern.\n\n"
    .. "Clicking a lantern flips it and the four lanterns beside it, lit to dark or dark to lit.\n\n"
    .. "Par is how many clicks the puzzle needs. Match it for three stars.",

  runes = "Work out the hidden code of four runes in ten tries.\n\n"
    .. "Fill a row from the runes below and press Unlock. A gold pip means a rune is right and in the right place. A silver pip means the rune is in the code but somewhere else. The pips don't say which rune they mean.\n\n"
    .. "Apprentice codes never repeat a rune. Master codes can.",

  pairs = "Turn over two cards at a time. If they match they stay up. If not, they turn back over.\n\n"
    .. "Find every pair in as few moves as you can.",

  quill = "Find the hidden five-letter word in six guesses.\n\n"
    .. "Gold with a bar: right letter, right spot. Blue with a dot: the letter is in the word somewhere else. Dark: not in the word.\n\n"
    .. "Use the keys on screen, or click the board to type and press Esc when you're done so your movement keys work again.\n\n"
    .. "Daily gives everyone the same word each day. Free play has as many words as you like.\n\n"
    .. "With Real words only on, guesses must be real words. Turn it off to try any five letters.",

  tapestry = "Use the number clues to work out which squares to weave and reveal a hidden picture.\n\n"
    .. "The numbers beside each row and above each column say how many woven squares are in a row there. A clue of 3 1 means three woven squares in a row, a gap, then one more. When a line matches its clue, its numbers fade.\n\n"
    .. "Left-click to weave, right-click to mark a square as empty, and drag to do several at once. Every puzzle can be solved by thinking it through, with no guessing.",

  ricochet = "Knock down the wall with the ember.\n\n"
    .. "Move the mouse over the board to steer the paddle and click to launch. Where the ember hits the paddle changes its angle.\n\n"
    .. "Catch falling tokens: the plank widens the paddle, the hourglass slows the ember, three embers add more embers and the heart gives you a life.",

  chimes = "Listen to the bells, then ring them back in the same order. The pattern is often a familiar tune.\n\n"
    .. "Each round adds one more bell. Classic ends at the first miss. Gentle plays slower and forgives one miss.",

  pegs = "Jump one peg over a neighbor into an empty hole. The peg you jump over is taken off the board.\n\n"
    .. "Click a peg, then one of the glowing holes. Keep going until no jumps are left.\n\n"
    .. "Leave just one peg to win. On the Cross board, finishing in the very middle is the best of all.",

  teahouse = "Clear the table by matching pairs of tiles with the same picture.\n\n"
    .. "A tile is free when nothing sits on top of it and it has an open side on its left or right. Dimmed tiles aren't free yet.\n\n"
    .. "Hint shows a pair you can take. Shuffle mixes the tiles if no pairs are left.",
}
