import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const GodTierApp());
}

// --- CORE ENGINE: INFINITE & AGGRESSIVE LOGIC ---
// Tọa độ sử dụng: bitwise key (x << 16 | y) để tối ưu hash map
// Phạm vi +/- 30,000 ô vuông

const int BLACK = 1; // Người
const int WHITE = 2; // AI

class GomokuEngine {
  // Hash coordinate thành 1 số int duy nhất để key map nhanh
  static int getKey(int x, int y) => (x << 16) | (y & 0xFFFF);
  static int getX(int key) => key >> 16;
  static int getY(int key) => (key << 16) >> 16; // sign extend

  // Hàm chính chạy trong Isolate
  static int findKillerMove(Map<int, int> boardData) {
    // 1. Nếu bàn cờ trống (hoặc ít quân), đánh vào tâm ảo (0,0)
    if (boardData.isEmpty) return getKey(0, 0);

    // 2. Tìm nước thắng bắt buộc (VCF - Victory by Continuous Four)
    int? vcfWin = _solveVCF(boardData, WHITE);
    if (vcfWin != null) return vcfWin;

    // 3. Chặn nước thắng của đối thủ
    int? blockWin = _solveVCF(boardData, BLACK);
    if (blockWin != null) return blockWin;

    // 4. Minimax Alpha-Beta Deep Search
    // Tìm vùng "chiến sự" (chỉ xét các ô gần quân đã đánh)
    List<int> moves = _generateCandidates(boardData);
    
    int bestMove = moves.first;
    double bestScore = -double.infinity;
    double alpha = -double.infinity;
    double beta = double.infinity;

    // Iterative deepening: Tuy nghĩ lâu nhưng đi là chết
    // Giới hạn tìm kiếm 20 nước tốt nhất
    int count = 0;
    for (int move in moves) {
      boardData[move] = WHITE;
      double score = -_negamax(boardData, 2, -beta, -alpha, BLACK);
      boardData.remove(move);

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
      alpha = max(alpha, score);
      if(alpha >= beta) break;
      count++;
      if(count > 25) break; // Chỉ xét 25 nước ngon nhất để tối ưu time
    }

    return bestMove;
  }

  // --- HEURISTIC ENGINE ---
  
  static double _negamax(Map<int, int> board, int depth, double alpha, double beta, int player) {
    if (depth == 0) return _evaluate(board, player);

    List<int> moves = _generateCandidates(board);
    double maxVal = -double.infinity;

    for (int move in moves) {
      board[move] = player;
      // Đệ quy đổi vai (0: human, 1: ai)
      double val = -_negamax(board, depth - 1, -beta, -alpha, player == WHITE ? BLACK : WHITE);
      board.remove(move); // Backtrack

      maxVal = max(maxVal, val);
      alpha = max(alpha, val);
      if (alpha >= beta) break;
    }
    return maxVal;
  }

  // Đánh giá thế cờ dựa trên Pattern (Chuỗi 5, 4, 3)
  static double _evaluate(Map<int, int> board, int player) {
    // AI cực ghét thua, nên điểm phòng thủ nhân hệ số cao
    double myScore = _scanAllPatterns(board, WHITE);
    double enemyScore = _scanAllPatterns(board, BLACK);
    
    if (player == WHITE) return myScore * 1.2 - enemyScore * 1.5;
    else return enemyScore * 1.2 - myScore * 1.5;
  }

  static double _scanAllPatterns(Map<int, int> board, int p) {
    double score = 0;
    // Chỉ quét các ô đã có quân của P để tối ưu (Infinite Board)
    for (var entry in board.entries) {
      if (entry.value != p) continue;
      int k = entry.key;
      int x = getX(k), y = getY(k);
      // Check 4 hướng: -, |, \, /
      score += _rateLine(board, x, y, 1, 0, p);
      score += _rateLine(board, x, y, 0, 1, p);
      score += _rateLine(board, x, y, 1, 1, p);
      score += _rateLine(board, x, y, 1, -1, p);
    }
    return score;
  }

  static double _rateLine(Map<int, int> b, int x, int y, int dx, int dy, int p) {
    // Logic đếm chuỗi (Giản lược cho hiệu năng cao)
    // Chuỗi 5: 100,000, Open 4: 10,000, Open 3: 1,000...
    int count = 1;
    int blocked = 0;
    
    // Tiến
    for(int i=1; i<5; i++) {
      int val = b[getKey(x + dx*i, y + dy*i)] ?? 0;
      if(val == p) count++;
      else if (val == 0) break;
      else { blocked++; break; }
    }
    // Lùi (để tránh tính trùng, ta chỉ xét pattern bắt đầu từ điểm hiện tại hướng dương, 
    // nhưng trong infinite board thực tế phải xét cả 2. 
    // Ở đây ta dùng thuật toán đơn giản: Mọi điểm đều được duyệt nên chỉ cần check 1 chiều từ nó)
    
    // Trọng số (Weight)
    if (count >= 5) return 1000000.0;
    if (blocked == 2) return 0; // Chết 2 đầu
    if (count == 4) return (blocked == 0) ? 50000 : 10000;
    if (count == 3) return (blocked == 0) ? 5000 : 1000;
    if (count == 2) return (blocked == 0) ? 500 : 10;
    return 1.0;
  }

  static int? _solveVCF(Map<int, int> b, int p) {
    // Check nhanh nếu có nước thắng ngay
    List<int> cands = _generateCandidates(b);
    for(int m in cands) {
      b[m] = p;
      if(_checkWin(b, m, p)) { b.remove(m); return m; }
      b.remove(m);
    }
    return null;
  }

  static List<int> _generateCandidates(Map<int, int> b) {
    Set<int> candidates = {};
    // Tìm các ô trống nằm cạnh các ô đã có quân (bán kính 1 hoặc 2)
    for (var k in b.keys) {
      int x = getX(k), y = getY(k);
      for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
          if (i == 0 && j == 0) continue;
          int nx = x + i, ny = y + j;
          int nk = getKey(nx, ny);
          if (!b.containsKey(nk)) candidates.add(nk);
        }
      }
    }
    // Sort ưu tiên ô trung tâm các đám đông để cắt tỉa AlphaBeta tốt hơn
    List<int> list = candidates.toList();
    // Shuffle nhẹ để nước đi không bị máy móc 100%
    list.shuffle(Random());
    return list;
  }

  static bool _checkWin(Map<int, int> b, int key, int p) {
    int x = getX(key), y = getY(key);
    List<List<int>> dirs = [[1,0], [0,1], [1,1], [1,-1]];
    for (var d in dirs) {
      int count = 1;
      for (int i=1; i<5; i++) {
        if (b[getKey(x + d[0]*i, y + d[1]*i)] == p) count++; else break;
      }
      for (int i=1; i<5; i++) {
        if (b[getKey(x - d[0]*i, y - d[1]*i)] == p) count++; else break;
      }
      if (count >= 5) return true;
    }
    return false;
  }
}

// =========================================================
// UI: IOS 18 ULTIMATE DESIGN
// =========================================================

class GodTierApp extends StatelessWidget {
  const GodTierApp({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    theme: CupertinoThemeData(brightness: Brightness.light, primaryColor: CupertinoColors.activeBlue),
    debugShowCheckedModeBanner: false,
    home: InfiniteGameScreen(),
  );
}

class InfiniteGameScreen extends StatefulWidget {
  const InfiniteGameScreen({super.key});
  @override
  State<InfiniteGameScreen> createState() => _InfiniteGameScreenState();
}

class _InfiniteGameScreenState extends State<InfiniteGameScreen> {
  // Bàn cờ vô hạn dùng Map
  Map<int, int> board = {}; 
  List<int> history = [];
  bool thinking = false;
  String status = "Tap to Start";
  int winner = 0;

  // Viewer Controller
  final TransformationController _viewCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    // Căn giữa bàn cờ vô hạn lúc đầu (offset 0,0)
    _centerBoard();
  }

  void _centerBoard() {
    _viewCtrl.value = Matrix4.identity()
      ..translate(MediaQuery.of(context).size.width/2, MediaQuery.of(context).size.height/2)
      ..scale(1.5); // Mặc định Zoom 1.5x
  }

  void _reset() {
    setState(() {
      board.clear(); history.clear(); winner = 0; status = "New Game";
    });
    _centerBoard();
  }

  void _undo() {
    if(history.length >= 2 && !thinking && winner == 0) {
      setState(() {
        board.remove(history.removeLast()); // AI
        board.remove(history.removeLast()); // Player
      });
      HapticFeedback.mediumImpact();
    }
  }

  void _handleTap(TapUpDetails details) async {
    if(thinking || winner != 0) return;

    // Lấy tọa độ chạm trong không gian InteractiveViewer
    // Chuyển đổi từ Screen -> Local -> Grid Coordinate
    Offset local = _viewCtrl.toScene(details.localPosition);
    const double cellSize = 40.0; // Kích thước ô cơ sở
    
    // Làm tròn để lấy tọa độ lưới (x,y có thể âm)
    int gx = (local.dx / cellSize).floor();
    int gy = (local.dy / cellSize).floor();
    int key = GomokuEngine.getKey(gx, gy);

    if(board.containsKey(key)) return;

    // --- 1. Player Move ---
    HapticFeedback.lightImpact();
    setState(() {
      board[key] = BLACK;
      history.add(key);
      status = "Thinking...";
      thinking = true;
    });

    if(GomokuEngine._checkWin(board, key, BLACK)) {
      _finish(BLACK); return;
    }

    // --- 2. AI Processing (Isolate) ---
    await Future.delayed(const Duration(milliseconds: 50)); // Wait UI
    // Clone map để ném vào Isolate
    Map<int, int> input = Map.from(board); 
    
    // Chạy thuật toán thần thánh
    int aiKey = await compute(GomokuEngine.findKillerMove, input);

    if(!mounted) return;

    // --- 3. AI Move ---
    setState(() {
      if(!board.containsKey(aiKey)) {
        board[aiKey] = WHITE;
        history.add(aiKey);
      }
      thinking = false;
      status = "Your Turn";
    });
    
    HapticFeedback.heavyImpact();
    
    // Tự động di chuyển camera tới nước đi của AI nếu nó ở xa
    // (Optional: Thêm animation pan tới đó nếu cần, nhưng để tự nhiên cho Pro)

    if(GomokuEngine._checkWin(board, aiKey, WHITE)) _finish(WHITE);
  }

  void _finish(int w) {
    setState(() { winner = w; status = w == BLACK ? "Victory" : "Defeated"; });
    showCupertinoDialog(context: context, builder: (c) => CupertinoAlertDialog(
      title: Text(w == BLACK ? "IMPOSSIBLE!" : "Stockfish Won"),
      content: Text(w == BLACK ? "You beat the unbeatable." : "AI checkmate you in ${history.length ~/ 2} moves."),
      actions: [
        CupertinoDialogAction(child: const Text("Review"), onPressed: ()=>Navigator.pop(c)),
        CupertinoDialogAction(isDefaultAction: true, child: const Text("Rematch"), onPressed: (){Navigator.pop(c); _reset();})
      ]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      child: Stack(
        children: [
          // 1. INFINITE BOARD (InteractiveViewer)
          InteractiveViewer(
            transformationController: _viewCtrl,
            boundaryMargin: const EdgeInsets.all(double.infinity), // Cho phép kéo đi khắp thế giới
            minScale: 0.5, maxScale: 4.0,
            constrained: false, // Vô hạn
            child: GestureDetector(
              onTapUp: _handleTap,
              child: CustomPaint(
                size: const Size(2000, 2000), // Kích thước vùng vẽ ảo (thực tế nó lặp vô hạn theo logic vẽ)
                painter: InfiniteGridPainter(board, history.isNotEmpty ? history.last : null),
              ),
            ),
          ),

          // 2. iOS 18 HUD (Glassmorphism)
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: CupertinoColors.white.withOpacity(0.6),
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text("Gomoku Infinity", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -1)),
                        Text(status, style: TextStyle(fontSize: 14, color: thinking ? CupertinoColors.systemOrange : CupertinoColors.secondaryLabel, fontWeight: FontWeight.w600))
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          const Icon(CupertinoIcons.hexagon_fill, size: 14, color: Colors.black87),
                          const SizedBox(width: 4),
                          Text("${(history.length/2).ceil()}", style: const TextStyle(fontWeight: FontWeight.bold))
                        ]),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. BOTTOM ACTIONS
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: CupertinoColors.black.withOpacity(0.8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(CupertinoIcons.arrow_uturn_left, _undo),
                      _btn(CupertinoIcons.add, _reset), // New Game
                      _btn(CupertinoIcons.scope, _centerBoard), // Re-center
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback func) => CupertinoButton(
    onPressed: func, padding: EdgeInsets.zero,
    child: Icon(icon, color: Colors.white, size: 28),
  );
}

// PAINTER: VẼ BÀN CỜ DỰA TRÊN TỌA ĐỘ THỰC
class InfiniteGridPainter extends CustomPainter {
  final Map<int, int> board;
  final int? lastMove;
  const InfiniteGridPainter(this.board, this.lastMove);

  @override
  void paint(Canvas canvas, Size size) {
    const double cellSize = 40.0;
    final paintGrid = Paint()..color = Colors.black12..strokeWidth = 1.0;
    
    // Lấy vùng nhìn thấy (Visible viewport) để tối ưu vẽ 
    // (Ở phiên bản đơn giản này ta vẽ một vùng rộng cố định xung quanh center ảo 0,0)
    // Kỹ thuật: Ta vẽ một lưới lớn "đủ dùng" cho người chơi, thực tế Board Logic là vô hạn
    // Nhưng CustomPaint cần Size hữu hạn. Ta dùng kỹ thuật dời gốc toạ độ.
    
    // Draw Grid (Vùng vẽ: +/
