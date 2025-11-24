import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui; // Sửa import để tránh conflict
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
  runApp(const GodApp());
}

// ===========================================================
// CORE ENGINE: KHÔNG THAY ĐỔI LOGIC SIÊU CẤP CỦA BẠN
// ===========================================================
const int P_HUMAN = 1; // BLACK
const int P_AI = 2;    // WHITE

class Engine {
  static int toKey(int x, int y) => (x << 16) | (y & 0xFFFF);
  static int getX(int k) => k >> 16;
  static int getY(int k) => (k << 16) >> 16;

  static int think(Map<int, int> board) {
    if (board.isEmpty) return toKey(0, 0);

    int? win = _solve(board, P_AI);
    if (win != null) return win;

    int? block = _solve(board, P_HUMAN);
    if (block != null) return block;

    // Deep Search Heuristic
    List<int> moves = _getArea(board);
    if (moves.isEmpty) return toKey(0, 0);

    int bestMove = moves[0];
    double maxS = -double.infinity;

    int limit = moves.length > 15 ? 15 : moves.length; // Chỉ lấy 15 nước tốt nhất để ko bị Timeout
    
    for (int i = 0; i < limit; i++) {
      int m = moves[i];
      double atk = _score(board, m, P_AI);
      double def = _score(board, m, P_HUMAN);
      // Chiến thuật: AI phải công (1.2) nhưng thủ cũng rất gắt (1.1)
      double score = atk * 1.2 + def * 1.1 + Random().nextDouble();
      
      if (score > maxS) { maxS = score; bestMove = m; }
    }
    return bestMove;
  }

  static int? _solve(Map<int, int> b, int p) {
    for (var k in _getArea(b)) {
      b[k] = p;
      if (_check(b, k, p)) { b.remove(k); return k; }
      b.remove(k);
    }
    return null;
  }

  static double _score(Map<int, int> b, int k, int p) {
    int x = getX(k), y = getY(k);
    double score = 0;
    // 4 Hướng
    score += _line(b, x, y, 1, 0, p);
    score += _line(b, x, y, 0, 1, p);
    score += _line(b, x, y, 1, 1, p);
    score += _line(b, x, y, 1, -1, p);
    return score;
  }

  static double _line(Map<int, int> b, int x, int y, int dx, int dy, int p) {
    int count = 0, open = 0;
    // Forward
    for(int i=1; i<5; i++) {
      int v = b[toKey(x+dx*i, y+dy*i)] ?? 0;
      if(v==p) count++; else if(v==0) { open++; break; } else break;
    }
    // Backward
    for(int i=1; i<5; i++) {
      int v = b[toKey(x-dx*i, y-dy*i)] ?? 0;
      if(v==p) count++; else if(v==0) { open++; break; } else break;
    }
    
    if (count >= 4) return 50000;
    if (count == 3) return (open > 0) ? 5000 : 100;
    if (count == 2) return (open > 1) ? 500 : 50;
    return (open > 0) ? 10 : 0;
  }

  static bool _check(Map<int, int> b, int k, int p) {
    int x = getX(k), y = getY(k);
    List<List<int>> dirs = [[1,0],[0,1],[1,1],[1,-1]];
    for(var d in dirs) {
      int c = 1;
      for(int i=1;i<5;i++) { if(b[toKey(x+d[0]*i, y+d[1]*i)] == p) c++; else break; }
      for(int i=1;i<5;i++) { if(b[toKey(x-d[0]*i, y-d[1]*i)] == p) c++; else break; }
      if(c >= 5) return true;
    }
    return false;
  }

  static List<int> _getArea(Map<int, int> b) {
    Set<int> s = {};
    for (int k in b.keys) {
      int x=getX(k), y=getY(k);
      for(int i=-1; i<=1; i++) for(int j=-1; j<=1; j++) {
        if(i==0 && j==0) continue;
        int nk = toKey(x+i, y+j);
        if(!b.containsKey(nk)) s.add(nk);
      }
    }
    return s.toList();
  }
}

// ===========================================================
// UI PRO: IOS 18 DESIGN + INFINITE CANVAS
// ===========================================================
class GodApp extends StatelessWidget {
  const GodApp({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    theme: CupertinoThemeData(brightness: Brightness.light, primaryColor: Color(0xFF007AFF)),
    debugShowCheckedModeBanner: false,
    home: InfiniteBoard(),
  );
}

class InfiniteBoard extends StatefulWidget {
  const InfiniteBoard({super.key});
  @override
  State<InfiniteBoard> createState() => _InfiniteBoardState();
}

class _InfiniteBoardState extends State<InfiniteBoard> {
  Map<int, int> board = {};
  List<int> history = [];
  bool busy = false;
  int winner = 0;
  final TransformationController _ctrl = TransformationController();

  @override
  void initState() {
    super.initState();
    // Center view (Screen Center -> Logical 0,0)
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final sz = MediaQuery.of(context).size;
        _ctrl.value = Matrix4.identity()..translate(sz.width/2, sz.height/2);
    });
  }

  void _reset() {
    setState(() { board.clear(); history.clear(); winner = 0; busy = false; });
  }

  void _undo() {
    if(history.length >= 2 && !busy && winner == 0) {
      setState(() {
        board.remove(history.removeLast());
        board.remove(history.removeLast());
      });
      HapticFeedback.selectionClick();
    }
  }

  void _tap(TapUpDetails d) async {
    if(busy || winner != 0) return;
    
    // Mapping to Grid
    Offset p = _ctrl.toScene(d.localPosition);
    const double SZ = 44.0;
    int gx = (p.dx / SZ).floor();
    int gy = (p.dy / SZ).floor();
    int key = Engine.toKey(gx, gy);

    if(board.containsKey(key)) return;

    // 1. Player
    HapticFeedback.lightImpact();
    setState(() { board[key] = P_HUMAN; history.add(key); busy = true; });
    if(Engine._check(board, key, P_HUMAN)) { _win(P_HUMAN); return; }

    // 2. AI
    await Future.delayed(const Duration(milliseconds: 20));
    Map<int, int> clone = Map.from(board);
    int aiKey = await compute(Engine.think, clone);

    if(!mounted) return;
    setState(() {
      board[aiKey] = P_AI; history.add(aiKey); busy = false;
    });
    HapticFeedback.heavyImpact();
    if(Engine._check(board, aiKey, P_AI)) { _win(P_AI); }
  }

  void _win(int p) {
    setState(() => winner = p);
    showCupertinoDialog(context: context, builder: (c) => CupertinoAlertDialog(
      title: Text(p==P_HUMAN ? "YOU WON!" : "GAME OVER"),
      content: Text(p==P_HUMAN ? "You are smarter than AI!" : "Stockfish is unstoppable."),
      actions: [CupertinoDialogAction(child: const Text("Play Again"), onPressed: (){
        Navigator.pop(c); _reset();
      })]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      child: Stack(
        children: [
          // --- CANVAS VÔ TẬN ---
          InteractiveViewer(
            transformationController: _ctrl,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.4, maxScale: 3.0, constrained: false,
            child: GestureDetector(
              onTapUp: _tap,
              child: CustomPaint(
                size: const Size(10000, 10000), // Virtual Size
                painter: BoardPainter(board, history.isNotEmpty ? history.last : null),
              ),
            ),
          ),
          
          // --- HUD GLASSMORPHISM ---
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRect(child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: CupertinoColors.white.withOpacity(0.6),
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Gomoku AI", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  if(busy) const CupertinoActivityIndicator()
                  else Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)),
                    child: Text(winner!=0?"Finish":"Moves: ${history.length}", style: const TextStyle(fontWeight: FontWeight.w600)),
                  )
                ]),
              )
            ))
          ),

          // --- BOTTOM CONTROLS ---
          Positioned(
            bottom: 30, left: 30, right: 30,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withOpacity(0.8),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0,5))]
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _iconBtn(CupertinoIcons.reply, _undo),
                  _iconBtn(CupertinoIcons.refresh, _reset),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _iconBtn(IconData i, VoidCallback f) => GestureDetector(
    onTap: f, child: Icon(i, color: Colors.white, size: 28)
  );
}

class BoardPainter extends CustomPainter {
  final Map<int, int> b;
  final int? last;
  BoardPainter(this.b, this.last);

  @override
  void paint(Canvas canvas, Size size) {
    const double SZ = 44.0;
    // Draw Grid
    final pLine = Paint()..color = Colors.black12..strokeWidth = 1.0;
    // Vẽ lưới xung quanh tâm ảo (Giả lập vô hạn) - phạm vi -50 đến +50 ô
    for (int i = -50; i <= 50; i++) {
      double v = i * SZ;
      canvas.drawLine(Offset(v, -50*SZ), Offset(v, 50*SZ), pLine);
      canvas.drawLine(Offset(-50*SZ, v), Offset(50*SZ, v), pLine);
    }

    // Draw Pieces
    final pBlack = Paint()..color = const Color(0xFF222222);
    final pWhite = Paint()..color = Colors.white..style=PaintingStyle.fill;
    final pWhiteStr = Paint()..color = Colors.black26..style=PaintingStyle.stroke..strokeWidth=1.5;
    final pShadow = Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    b.forEach((k, v) {
      int gx = Engine.getX(k), gy = Engine.getY(k);
      Offset c = Offset(gx * SZ + SZ/2, gy * SZ + SZ/2);
      
      canvas.drawCircle(c.translate(1, 2), SZ*0.4, pShadow); // Shadow
      if(v==P_HUMAN) {
        canvas.drawCircle(c, SZ*0.4, pBlack);
      } else {
        canvas.drawCircle(c, SZ*0.4, pWhite);
        canvas.drawCircle(c, SZ*0.4, pWhiteStr);
      }
      
      if(k==last) {
        canvas.drawCircle(c, 4, Paint()..color=CupertinoColors.systemRed);
      }
    });
  }
  @override
  bool shouldRepaint(covariant BoardPainter o) => true;
}
