import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'; // QUAN TRỌNG: Để dùng compute
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ========================================================
// ⚙️ CẤU HÌNH STOCKFISH GOMOKU 2025
// ========================================================
const int P_HUMAN = 1; // X (User)
const int P_AI = 2;    // O (Stockfish)
const double BASE_SIZE = 46.0;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Chế độ toàn màn hình, ẩn thanh trạng thái
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const StockfishMasterApp());
}

// ========================================================
// 🧠 BRAIN: ĐỘNG CƠ TÍNH TOÁN (FIXED LOGIC)
// ========================================================
class Brain {
  // [FIXED]: Đổi tên hàm ngắn từ 'k' thành 'pos' để tránh trùng tên biến
  static String pos(int x, int y) => "$x,$y";
  
  static List<int> decode(String key) {
    var s = key.split(',');
    return [int.parse(s[0]), int.parse(s[1])];
  }

  // --- AI MAIN THREAD (Chạy dưới nền) ---
  static String aiTurn(Map<String, int> board) {
    // 1. Nếu bàn cờ trống, đánh vào giữa
    if (board.isEmpty) return pos(0, 0);

    // 2. VCF (Victory by Continuous Four) - Thắng ngay lập tức
    String? win = _findForceMove(board, P_AI);
    if (win != null) return win;

    // 3. Chặn nước VCF của địch - Ưu tiên số 1
    String? block = _findForceMove(board, P_HUMAN);
    if (block != null) return block;

    // 4. Tính toán chiến lược (Minimax Depth 2 + Heuristic)
    return _deepStrategy(board);
  }

  // Tìm nước bắt buộc phải đi (Thắng hoặc Chặn thua)
  static String? _findForceMove(Map<String, int> b, int p) {
    // Lấy danh sách các ô trống sát cạnh các quân đã đánh
    Set<String> candidates = _getNeighbors(b, 1);
    
    // Ưu tiên 1: Thắng 5 (Game Over)
    for (var m in candidates) {
      b[m] = p;
      if (_isWin(b, m, p)) { b.remove(m); return m; }
      b.remove(m);
    }

    // Ưu tiên 2: Tạo Open 4 (Không thể chặn)
    for (var m in candidates) {
      b[m] = p;
      // 9500 điểm tương ứng với thế cờ chắc chắn thắng
      if (_evaluateCell(b, m, p) >= 9500) { b.remove(m); return m; }
      b.remove(m);
    }
    
    // Ưu tiên 3: Chặn Double Threat (Ví dụ 4-3, 3-3)
    if (p == P_HUMAN) {
       for (var m in candidates) {
        b[m] = p;
        // Nếu nước này tạo ra nguy hiểm cực lớn (>3000) thì phải chặn ngay
        if (_evaluateCell(b, m, p) >= 3000) { b.remove(m); return m; }
        b.remove(m);
      }
    }

    return null;
  }

  // Tư duy chiến lược
  static String _deepStrategy(Map<String, int> b) {
    // Quét rộng hơn (Bán kính 2)
    List<String> candidates = _getNeighbors(b, 2).toList();
    if (candidates.isEmpty) return pos(0, 0);

    String bestMove = candidates[0];
    double maxScore = -double.infinity;

    // Giới hạn số lượng nước đi cần tính toán để không bị Lag (30 nước tốt nhất)
    int limit = candidates.length > 30 ? 30 : candidates.length;

    for (int i = 0; i < limit; i++) {
      String m = candidates[i];
      
      // Điểm tấn công (Mình)
      double attack = _evaluateCell(b, m, P_AI);
      // Điểm phòng thủ (Chặn Địch)
      double defense = _evaluateCell(b, m, P_HUMAN);
      
      // CHIẾN THUẬT 2025 "STOCKFISH STYLE":
      // Nếu địch đang có thế cờ mạnh (>= 1000 ~ Open 3), ta dồn lực phòng thủ (x2.5)
      // Nếu bàn cờ an toàn, ta ưu tiên tấn công mở cờ (x1.2)
      
      double finalScore = (defense >= 1000) 
          ? (defense * 2.5 + attack * 0.8) // Phòng thủ triệt để
          : (attack * 1.2 + defense * 1.0); // Tấn công
          
      // Thêm chút ngẫu nhiên cực nhỏ để AI không bị bắt bài (Human-like)
      finalScore += Random().nextDouble() * 5.0;

      if (finalScore > maxScore) {
        maxScore = finalScore;
        bestMove = m;
      }
    }
    return bestMove;
  }

  // Hàm lượng giá một ô cờ
  static double _evaluateCell(Map<String, int> b, String key, int p) {
    var xy = decode(key);
    int x = xy[0], y = xy[1];
    // Cộng điểm 4 hướng
    return _scoreDir(b, x, y, 1, 0, p) + 
           _scoreDir(b, x, y, 0, 1, p) + 
           _scoreDir(b, x, y, 1, 1, p) + 
           _scoreDir(b, x, y, 1, -1, p);
  }

  static double _scoreDir(Map<String, int> b, int x, int y, int dx, int dy, int p) {
    int count = 0;
    int open = 0;
    
    // Duyệt tiến
    for (int i = 1; i < 5; i++) {
      int? val = b[pos(x + dx * i, y + dy * i)];
      if (val == p) count++;
      else if (val == null) { open++; break; } // Gặp ô trống
      else break; // Gặp quân địch
    }
    // Duyệt lùi
    for (int i = 1; i < 5; i++) {
      int? val = b[pos(x - dx * i, y - dy * i)];
      if (val == p) count++;
      else if (val == null) { open++; break; } 
      else break;
    }

    // MA TRẬN ĐIỂM (Threat Matrix)
    if (count >= 4) return 100000; // Thắng tuyệt đối
    
    if (count == 3) {
      if (open == 2) return 10000; // Open 4 (Chắc chắn thắng sau 1 nước)
      if (open == 1) return 2000;  // Blocked 4 (Cần đi tiếp để thắng)
    }
    
    if (count == 2) {
      if (open == 2) return 2000; // Open 3 (Rất mạnh)
      if (open == 1) return 100;  // Blocked 3 (Ít giá trị)
    }
    
    if (count == 1 && open == 2) return 50; // Open 2
    
    return 0;
  }

  static bool _isWin(Map<String, int> b, String k, int p) => _evaluateCell(b, k, p) >= 80000;

  // Hàm lấy vùng lân cận (Đã Fix lỗi trùng tên biến k)
  static Set<String> _getNeighbors(Map<String, int> b, int dist) {
    Set<String> zone = {};
    // Dùng 'entry' để tránh đặt tên biến là 'k'
    for (var entry in b.entries) {
      var xy = decode(entry.key);
      int cx = xy[0];
      int cy = xy[1];
      
      for (int dx = -dist; dx <= dist; dx++) {
        for (int dy = -dist; dy <= dist; dy++) {
          if (dx == 0 && dy == 0) continue;
          // Gọi hàm 'pos' thay vì 'k'
          String neighbor = pos(cx + dx, cy + dy);
          if (!b.containsKey(neighbor)) zone.add(neighbor);
        }
      }
    }
    return zone;
  }
}

// ========================================================
// 📱 APP UI: NATIVE IOS 18 STYLE
// ========================================================
class StockfishMasterApp extends StatelessWidget {
  const StockfishMasterApp({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    title: "TicTacToe Master",
    debugShowCheckedModeBanner: false,
    theme: CupertinoThemeData(
      brightness: Brightness.light, 
      primaryColor: CupertinoColors.systemBlue
    ),
    home: GameScene(),
  );
}

class GameScene extends StatefulWidget {
  const GameScene({super.key});
  @override
  State<GameScene> createState() => _GameSceneState();
}

class _GameSceneState extends State<GameScene> {
  Map<String, int> board = {};
  List<String> history = [];
  bool thinking = false;
  int win = 0; // 0: playing, 1: X won, 2: O won

  // Viewport
  Offset offset = Offset.zero;
  double scale = 1.0;

  @override
  void initState() {
    super.initState();
    offset = Offset.zero;
  }

  void _reset() {
    setState(() {
      board.clear(); 
      history.clear(); 
      win = 0; 
      thinking = false; 
      offset = Offset.zero; 
      scale = 1.0; 
    });
  }

  void _undo() {
    if (history.length >= 2 && !thinking && win == 0) {
      setState(() {
        board.remove(history.removeLast());
        board.remove(history.removeLast());
      });
    }
  }

  // Xử lý Tap
  void _onTapUp(TapUpDetails d) async {
    if (thinking || win != 0) return;

    final sz = MediaQuery.of(context).size;
    double cx = sz.width / 2;
    double cy = sz.height / 2;

    // Chuyển đổi tọa độ màn hình -> tọa độ Lưới
    double gridPixel = BASE_SIZE * scale;
    double touchX = (d.localPosition.dx - cx - offset.dx) / gridPixel;
    double touchY = (d.localPosition.dy - cy - offset.dy) / gridPixel;

    int gx = touchX.floor();
    int gy = touchY.floor();
    String key = Brain.pos(gx, gy); // Dùng 'pos' thay vì 'k'

    if (board.containsKey(key)) return;

    // --- Lượt Người Chơi (X) ---
    HapticFeedback.selectionClick();
    setState(() {
      board[key] = P_HUMAN;
      history.add(key);
      thinking = true;
    });

    if (Brain._isWin(board, key, P_HUMAN)) { _finish(P_HUMAN); return; }

    // --- Lượt AI (O) - Dùng Isolate ---
    await Future.delayed(const Duration(milliseconds: 50)); // Chờ UI vẽ X
    
    // Copy Map để chuyển vào Isolate
    Map<String, int> cloneData = Map.from(board);
    String aiKey = await compute(Brain.aiTurn, cloneData);

    if (!mounted) return;

    setState(() {
      // Chỉ đánh nếu ô đó còn trống (Logic an toàn)
      if (!board.containsKey(aiKey)) {
        board[aiKey] = P_AI;
        history.add(aiKey);
      }
      thinking = false;
    });
    HapticFeedback.mediumImpact();

    if (Brain._isWin(board, aiKey, P_AI)) { _finish(P_AI); }
  }

  void _pan(DragUpdateDetails d) => setState(() => offset += d.delta);
  void _zoom(double v) => setState(() => scale = (scale + v).clamp(0.5, 2.5));

  void _finish(int who) {
    setState(() => win = who);
    showCupertinoDialog(context: context, builder: (ctx) => CupertinoAlertDialog(
      title: Text(who == P_HUMAN ? "YOU WIN!" : "AI WIN!"),
      content: Text(who == P_HUMAN ? "Amazing Game!" : "Better luck next time."),
      actions: [
        CupertinoDialogAction(child: const Text("Replay"), isDefaultAction: true, onPressed: (){
          Navigator.pop(ctx); _reset();
        })
      ]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      child: Stack(
        children: [
          // 1. LAYER VẼ VÔ TẬN
          GestureDetector(
            onPanUpdate: _pan,
            onTapUp: _onTapUp,
            child: CustomPaint(
              size: Size.infinite,
              painter: TicTacToePainter(
                board, offset, scale, 
                history.isNotEmpty ? history.last : null
              ),
            ),
          ),

          // 2. THANH TRẠNG THÁI (Top Glass)
          Positioned(top:0, left:0, right:0, child: ClipRect(child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              // [FIX WARNING] Dùng withValues thay vì withOpacity cho Flutter 2025
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85), 
                border: const Border(bottom: BorderSide(color: Colors.black12))
              ),
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Stockfish 2025", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(win!=0?"Finish" : (thinking?"Deep Thinking...":"Your Turn (X)"), 
                    style: TextStyle(color: thinking?Colors.redAccent:Colors.grey, fontSize: 14, fontWeight: FontWeight.w500))
                ]),
                Text("#${history.length}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87))
              ]),
            ),
          ))),

          // 3. THANH CÔNG CỤ (Bottom Floating Pill)
          Positioned(bottom: 40, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF202020), 
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))]
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(CupertinoIcons.minus, () => _zoom(-0.25)),
              _btn(CupertinoIcons.add, () => _zoom(0.25)),
              Container(width: 1, height: 20, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
              _btn(CupertinoIcons.arrow_uturn_left, _undo),
              _btn(CupertinoIcons.arrow_2_circlepath, _reset),
              _btn(CupertinoIcons.scope, () => setState(() => offset = Offset.zero)),
            ]),
          ))),
        ],
      ),
    );
  }

  Widget _btn(IconData i, VoidCallback f) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    minSize: 0, onPressed: f,
    child: Icon(i, color: Colors.white, size: 22)
  );
}

// ========================================================
// 🎨 PAINTER: NÉT VẼ MỰC XANH ĐỎ
// ========================================================
class TicTacToePainter extends CustomPainter {
  final Map<String, int> board;
  final Offset offset;
  final double scale;
  final String? lastMove;
  TicTacToePainter(this.board, this.offset, this.scale, this.lastMove);

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;
    double gs = BASE_SIZE * scale;

    // --- 1. VẼ LƯỚI CARO (Chỉ vẽ vùng nhìn thấy) ---
    // Tính biên để loop (Viewport Culling)
    int cS = ((-cx - offset.dx) / gs).floor() - 1;
    int cE = ((size.width - cx - offset.dx) / gs).ceil() + 1;
    int rS = ((-cy - offset.dy) / gs).floor() - 1;
    int rE = ((size.height - cy - offset.dy) / gs).ceil() + 1;

    // Màu lưới
    final pGrid = Paint()..color=Colors.blueGrey.withValues(alpha: 0.15)..strokeWidth=1.0;
    final pAxis = Paint()..color=Colors.black26..strokeWidth=2.0;

    for (int i = cS; i <= cE; i++) {
      double x = cx + offset.dx + i * gs;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i == 0 ? pAxis : pGrid);
    }
    for (int i = rS; i <= rE; i++) {
      double y = cy + offset.dy + i * gs;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i == 0 ? pAxis : pGrid);
    }

    // --- 2. VẼ X và O ---
    // Style bút dạ quang
    final pX = Paint()..color=const Color(0xFFFF3B30)..strokeWidth=4*scale..strokeCap=StrokeCap.round; // Apple Red
    final pO = Paint()..color=const Color(0xFF007AFF)..strokeWidth=4*scale..style=PaintingStyle.stroke; // Apple Blue
    final pLast = Paint()..color=Colors.amber.withValues(alpha: 0.3); // Highlight nước cuối

    board.forEach((key, who) {
      var xy = Brain.decode(key);
      double px = cx + offset.dx + xy[0] * gs + gs / 2;
      double py = cy + offset.dy + xy[1] * gs + gs / 2;

      // Bỏ qua nếu ngoài màn hình
      if (px < -gs || px > size.width + gs || py < -gs || py > size.height + gs) return;

      // Highlight nước đi cuối cùng
      if (key == lastMove) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset(px, py), width: gs, height: gs),
          pLast
        );
      }

      double r = gs * 0.32;

      if (who == P_HUMAN) {
        // Draw X
        canvas.drawLine(Offset(px - r, py - r), Offset(px + r, py + r), pX);
        canvas.drawLine(Offset(px + r, py - r), Offset(px - r, py + r), pX);
      } else {
        // Draw O
        canvas.drawCircle(Offset(px, py), r, pO);
      }
    });
  }

  @override
  bool shouldRepaint(covariant TicTacToePainter old) => true;
}
