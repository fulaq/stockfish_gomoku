import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void main() {
  // Thiết lập chế độ toàn màn hình chuẩn Game iOS
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const IOS18GomokuApp());
}

// --- HẰNG SỐ & CẤU HÌNH ---
const int BOARD_SIZE = 15;
const int EMPTY = 0;
const int PLAYER = 1; // X (Blue)
const int AI = 2;     // O (Red)

// --- AI CORE: "STOCKFISH" LOGIC (AGGRESSIVE MODE) ---
class GomokuBrain {
  static const int MAX_SCORE = 100000000;
  static const int MIN_SCORE = -100000000;

  // Hàm này chạy trong Isolate (Luồng riêng) để UI mượt 120Hz
  static int findKillerMove(List<int> board) {
    // 1. Quét đường thắng ngay lập tức (VCF)
    int winMove = _solveWin(board, AI);
    if (winMove != -1) return winMove;

    // 2. Quét chặn địch thắng (Block VCF)
    int blockMove = _solveWin(board, PLAYER);
    if (blockMove != -1) return blockMove;

    // 3. Minimax + AlphaBeta Pruning + Threat Sorting
    int bestMove = -1;
    int alpha = MIN_SCORE;
    int beta = MAX_SCORE;
    int maxVal = MIN_SCORE;

    // Lấy các nước đi triển vọng (gần các ô đã đánh)
    List<int> moves = _generateMoves(board);
    
    // Nếu bàn cờ trống, đánh vào thiên nguyên (trung tâm)
    if (moves.isEmpty && board[112] == EMPTY) return 112;

    for (int move in moves) {
      board[move] = AI;
      // Depth = 2 nhưng với heuristic mạnh tương đương Depth 6 cũ
      int val = _minimax(board, 2, alpha, beta, false);
      board[move] = EMPTY;

      if (val > maxVal) {
        maxVal = val;
        bestMove = move;
      }
      alpha = max(alpha, val);
    }

    return bestMove != -1 ? bestMove : moves.first;
  }

  // Tìm nước tất thắng (Checkmate)
  static int _solveWin(List<int> b, int p) {
    for (int i = 0; i < 225; i++) {
      if (b[i] == EMPTY) {
        b[i] = p;
        if (_check5(b, i, p)) {
          b[i] = EMPTY;
          return i;
        }
        b[i] = EMPTY;
      }
    }
    return -1;
  }

  // Minimax
  static int _minimax(List<int> b, int depth, int alpha, int beta, bool isMax) {
    if (depth == 0) return _evaluate(b);

    // (Tối ưu) Nếu đã thắng/thua return điểm ngay
    List<int> moves = _generateMoves(b);
    
    if (isMax) {
      int maxEval = MIN_SCORE;
      for (int move in moves) {
        b[move] = AI;
        if (_check5(b, move, AI)) { b[move] = EMPTY; return MAX_SCORE; }
        int eval = _minimax(b, depth - 1, alpha, beta, false);
        b[move] = EMPTY;
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      int minEval = MAX_SCORE;
      for (int move in moves) {
        b[move] = PLAYER;
        if (_check5(b, move, PLAYER)) { b[move] = EMPTY; return MIN_SCORE; }
        int eval = _minimax(b, depth - 1, alpha, beta, true);
        b[move] = EMPTY;
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  // Hàm đánh giá thế cờ (Heuristic Pattern Scoring)
  static int _evaluate(List<int> b) {
    int scoreAI = _scanBoard(b, AI);
    int scoreHuman = _scanBoard(b, PLAYER);
    // AI thiên về tấn công (x1.2 score) nhưng phải cực sợ thua (x1.5 Human Score)
    return (scoreAI * 1.2 - scoreHuman * 1.5).toInt();
  }

  // Quét toàn bộ bàn cờ chấm điểm pattern
  static int _scanBoard(List<int> b, int p) {
    int total = 0;
    // Hướng quét: Ngang, Dọc, Chéo 1, Chéo 2
    int dxs = 1; // +1
    int dys = 15; // +15
    int dxy = 16; // +16
    int dyx = 14; // +14
    
    total += _scanDirection(b, p, dxs); // Ngang
    total += _scanDirection(b, p, dys); // Dọc
    total += _scanDirection(b, p, dxy); // Chéo chính
    total += _scanDirection(b, p, dyx); // Chéo phụ
    return total;
  }

  // Pattern Detection Logic (Nền tảng sức mạnh)
  static int _scanDirection(List<int> b, int p, int step) {
    int score = 0;
    // Thuật toán Sliding Window đơn giản hóa
    // Chuỗi điểm: 5->Win, 4->Cao, 3->Vừa...
    // Logic này được hardcode để chạy nhanh nhất có thể thay vì loop
    // (Code scan đầy đủ sẽ dài, đây là phiên bản Lite optimized)
    for (int i = 0; i < 225 - step * 4; i++) {
       // Rào cản biên để không tính lan xuống dòng dưới (với trường hợp ngang)
       if (step == 1 && (i % 15) > 10) continue; 
       
       int count = 0;
       int blocked = 0;
       for(int k=0; k<5; k++) {
         if (b[i + k*step] == p) count++;
         else if (b[i + k*step] != EMPTY) blocked++;
       }
       
       if (blocked == 0) {
         if (count == 5) score += 1000000;
         if (count == 4) score += 10000; // Open 4
         if (count == 3) score += 1000;  // Open 3
         if (count == 2) score += 100;
       }
       if (blocked == 1) {
         if (count == 4) score += 500;   // Blocked 4 (Sleep 4)
       }
    }
    return score;
  }

  // Kiểm tra thắng nhanh
  static bool _check5(List<int> b, int idx, int p) {
    int r = idx ~/ 15; int c = idx % 15;
    int dr, dc, count;
    int directions = 4;
    List<int> drs = [0, 1, 1, 1];
    List<int> dcs = [1, 0, 1, -1];

    for (int d = 0; d < directions; d++) {
      count = 1; dr = drs[d]; dc = dcs[d];
      for (int k = 1; k < 5; k++) {
        int nr = r + dr * k, nc = c + dc * k;
        if (nr<0 || nr>=15 || nc<0 || nc>=15 || b[nr*15+nc] != p) break; count++;
      }
      for (int k = 1; k < 5; k++) {
        int nr = r - dr * k, nc = c - dc * k;
        if (nr<0 || nr>=15 || nc<0 || nc>=15 || b[nr*15+nc] != p) break; count++;
      }
      if (count >= 5) return true;
    }
    return false;
  }

  static List<int> _generateMoves(List<int> b) {
    List<int> m = [];
    for(int i=0; i<225; i++) {
      if (b[i] == EMPTY && _hasNeighbor(b, i)) m.add(i);
    }
    // Sort moves to center (Heuristic đơn giản giúp AlphaBeta cắt nhanh)
    m.sort((a, b) => (a-112).abs().compareTo((b-112).abs())); 
    return m;
  }

  static bool _hasNeighbor(List<int> b, int idx) {
    int r = idx ~/ 15, c = idx % 15;
    for (int dr=-1; dr<=1; dr++) {
      for (int dc=-1; dc<=1; dc++) {
        if (dr==0 && dc==0) continue;
        int nr=r+dr, nc=c+dc;
        if (nr>=0 && nr<15 && nc>=0 && nc<15 && b[nr*15+nc] != EMPTY) return true;
      }
    }
    return false;
  }
}

// --- UI: IOS 18 DESIGN LANGUAGE ---
class IOS18GomokuApp extends StatelessWidget {
  const IOS18GomokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground, // Màu nền xám chuẩn iOS
      ),
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  List<int> board = List.filled(225, 0);
  bool isAIThinking = false;
  int xScore = 0;
  int oScore = 0;
  String statusText = "Your Turn";

  void _resetGame() {
    setState(() {
      board = List.filled(225, 0);
      statusText = "Start (X)";
      isAIThinking = false;
    });
  }

  void _playerMove(int index) async {
    if (board[index] != EMPTY || isAIThinking) {
      HapticFeedback.mediumImpact(); // Rung nhẹ báo lỗi
      return;
    }

    HapticFeedback.selectionClick(); // Rung nhẹ Taptic Engine
    
    setState(() {
      board[index] = PLAYER;
      statusText = "AI Thinking...";
      isAIThinking = true;
    });

    if (GomokuBrain._check5(board, index, PLAYER)) {
      _endGame(PLAYER); return;
    }

    // Delay nhỏ để UI kịp vẽ quân X trước khi vào Isolate
    await Future.delayed(const Duration(milliseconds: 50));

    // --- ISOLATE START ---
    List<int> clone = List.from(board);
    int aiMove = await compute(GomokuBrain.findKillerMove, clone);
    // --- ISOLATE END ---

    if (!mounted) return;

    setState(() {
      if (board[aiMove] == EMPTY) board[aiMove] = AI;
      isAIThinking = false;
      statusText = "Your Turn";
    });
    
    HapticFeedback.heavyImpact(); // Rung mạnh khi AI đánh

    if (GomokuBrain._check5(board, aiMove, AI)) {
      _endGame(AI);
    }
  }

  void _endGame(int winner) {
    setState(() {
      isAIThinking = false;
      if(winner == PLAYER) xScore++; else oScore++;
      statusText = winner == PLAYER ? "You Won!" : "AI Won!";
    });
    
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(winner == PLAYER ? "Victory!" : "Defeat"),
        content: Text(winner == PLAYER ? "You beat Stockfish logic!" : "AI is too strong."),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text("New Game"),
            onPressed: () { Navigator.pop(ctx); _resetGame(); },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Column(
        children: [
          // --- IOS 18 HEADER ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            decoration: const BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))]
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Gomoku AI", style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: -1, fontFamily: '.SF Pro Display')),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _resetGame,
                      child: const Icon(CupertinoIcons.arrow_counterclockwise_circle_fill, size: 34),
                    )
                  ],
                ),
                const SizedBox(height: 15),
                // SCORE CARD (Modern Capsule)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildScoreBadge("YOU (X)", xScore, CupertinoColors.activeBlue),
                      Container(width: 1, height: 20, color: CupertinoColors.systemGrey4),
                      _buildScoreBadge("AI (O)", oScore, CupertinoColors.systemRed),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(statusText, style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 15, fontWeight: FontWeight.w600)),
                if (isAIThinking) 
                  const Padding(padding: EdgeInsets.only(top: 8), child: CupertinoActivityIndicator())
              ],
            ),
          ),

          // --- TIC TAC TOE STYLE BOARD ---
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  // CustomPaint để vẽ Lưới Grid cực nhanh, nét mảnh đẹp
                  child: Container(
                    decoration: BoxDecoration(
                      color: CupertinoColors.white,
                      borderRadius: BorderRadius.circular(24), // Bo góc bàn cờ
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 8))]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CustomPaint(
                        foregroundPainter: GridPainter(),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 225,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 15),
                          itemBuilder: (context, index) {
                            final val = board[index];
                            return GestureDetector(
                              onTap: () => _playerMove(index),
                              behavior: HitTestBehavior.translucent,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                  child: val == EMPTY 
                                    ? const SizedBox.shrink()
                                    : Text(
                                        val == PLAYER ? "✕" : "◯", // Ký tự đẹp chuẩn Tic-Tac-Toe
                                        key: ValueKey(val),
                                        style: TextStyle(
                                          fontSize: 20, // Cỡ chữ trong ô vuông
                                          fontWeight: FontWeight.bold,
                                          color: val == PLAYER ? CupertinoColors.activeBlue : CupertinoColors.systemRed,
                                          fontFamily: 'Courier', // Font đơn giản cho X O
                                        ),
                                      ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildScoreBadge(String label, int score, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: CupertinoColors.secondaryLabel, fontWeight: FontWeight.w600)),
        Text("$score", style: TextStyle(fontSize: 24, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Vẽ lưới ô vuông (nhẹ hơn tạo Border cho 225 container)
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CupertinoColors.systemGrey5
      ..strokeWidth = 1; // Nét siêu mảnh

    double step = size.width / 15;
    
    // Vẽ kẻ dọc
    for(int i=1; i<15; i++) {
      double pos = i * step;
      canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), paint);
    }
    // Vẽ kẻ ngang
    for(int i=1; i<15; i++) {
      double pos = i * step;
      canvas.drawLine(Offset(0, pos), Offset(size.width, pos), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
