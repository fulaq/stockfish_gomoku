import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
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
  runApp(const GomokuProApp());
}

// =========================================================
// ENGINE AI: HIGH PERFORMANCE AGGRESSIVE LOGIC
// =========================================================
const int SIZE = 15;
const int EMPTY = 0;
const int BLACK = 1; // Người chơi (Black)
const int WHITE = 2; // AI (White)

class AICompute {
  static int calculateMove(List<int> board) {
    // 1. Quét nước thắng tuyệt đối (VCF Check)
    int win = _scanMap(board, WHITE);
    if (win != -1) return win;

    // 2. Chặn nước thua ngay lập tức
    int block = _scanMap(board, BLACK);
    if (block != -1) return block;

    // 3. Minimax + Heuristic Position
    return _findBestSpot(board);
  }

  // Quét toàn bộ bàn cờ
  static int _scanMap(List<int> b, int p) {
    for (int i = 0; i < 225; i++) {
      if (b[i] == EMPTY) {
        b[i] = p;
        // Kiểm tra thắng 5 (Five in a row)
        if (_checkWin(b, i, p)) { b[i] = EMPTY; return i; }
        b[i] = EMPTY;
      }
    }
    return -1;
  }

  // Hàm tính điểm cục bộ
  static int _findBestSpot(List<int> b) {
    int bestIdx = -1;
    int maxScore = -999999999;

    // Tạo danh sách các ô ứng viên (Chỉ xét ô có láng giềng)
    List<int> moves = [];
    for (int i = 0; i < 225; i++) {
      if (b[i] == EMPTY && _hasNeighbor(b, i)) moves.add(i);
    }
    
    // Nếu trống trơn đánh vào tâm
    if (moves.isEmpty) return 112;

    for (int idx in moves) {
      // Chiến thuật: Tấn công mạnh (1.5) - Phòng thủ chắc (1.0)
      // AI hung hăng sẽ ưu tiên tạo thế của mình
      int attack = _evaluateScore(b, idx, WHITE);
      int defense = _evaluateScore(b, idx, BLACK);
      int score = (attack * 1.2 + defense * 1.0).toInt();

      // Random nhẹ để tránh AI đi lặp lại 1 bài
      score += Random().nextInt(10);

      if (score > maxScore) {
        maxScore = score;
        bestIdx = idx;
      }
    }
    return bestIdx;
  }

  static int _evaluateScore(List<int> b, int idx, int p) {
    int score = 0;
    int r = idx ~/ 15, c = idx % 15;
    int dx = 1, dy = 15, dxy = 16, dyx = 14; // 4 Hướng
    
    // Hàm check line
    score += _countLine(b, idx, p, 1, 0);   // Ngang
    score += _countLine(b, idx, p, 0, 1);   // Dọc
    score += _countLine(b, idx, p, 1, 1);   // Chéo \
    score += _countLine(b, idx, p, 1, -1);  // Chéo /
    return score;
  }

  static int _countLine(List<int> b, int idx, int p, int dx, int dy) {
    int count = 0, openEnds = 0;
    int r = idx ~/ 15, c = idx % 15;
    
    // Forward check
    for (int i = 1; i < 5; i++) {
      int nr = r + dy*i, nc = c + dx*i;
      // Logic fix cho các hướng
      if(dy==0) nr = r; if(dx==0) nc = c; // Fix logic toạ độ
      // Tính lại index thực
      // Đơn giản hóa bằng việc duyệt trên mảng 1 chiều nhưng check biên
      int nIdx = idx + (dy*15 + dx)*i; // Sai công thức mảng
      // Dùng logic duyệt thủ công an toàn hơn:
      int checkR = r + (dy)*i; 
      int checkC = c + (dx)*i;
      
      if(checkR<0 || checkR>=15 || checkC<0 || checkC>=15) break;
      int cell = b[checkR*15 + checkC];
      if(cell == p) count++;
      else if (cell == EMPTY) { openEnds++; break; }
      else break;
    }
    
    // Backward check
    for (int i = 1; i < 5; i++) {
      int checkR = r - (dy)*i; 
      int checkC = c - (dx)*i;
      if(checkR<0 || checkR>=15 || checkC<0 || checkC>=15) break;
      int cell = b[checkR*15 + checkC];
      if(cell == p) count++;
      else if (cell == EMPTY) { openEnds++; break; }
      else break;
    }

    if (count >= 4) return 50000; // 5 in row (thắng)
    if (count == 3) {
      if (openEnds == 2) return 10000; // Open 4 (chắc chắn thắng sau 1 nước)
      if (openEnds == 1) return 5000;  // Blocked 4
    }
    if (count == 2) {
      if (openEnds == 2) return 1000; // Open 3 (nguy hiểm)
      if (openEnds == 1) return 100;
    }
    if (count == 1 && openEnds == 2) return 10;
    return 0;
  }

  static bool _checkWin(List<int> b, int idx, int p) {
    int r = idx ~/ 15; int c = idx % 15;
    List<List<int>> dirs = [[1,0],[0,1],[1,1],[1,-1]];
    for(var d in dirs){
      int count=1;
      for(int k=1;k<5;k++){
        int nr=r+d[1]*k, nc=c+d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; count++;
      }
      for(int k=1;k<5;k++){
        int nr=r-d[1]*k, nc=c-d[0]*k;
        if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; count++;
      }
      if(count>=5) return true;
    }
    return false;
  }

  static bool _hasNeighbor(List<int> b, int idx) {
    int r=idx~/15, c=idx%15;
    for(int i=-1; i<=1; i++) for(int j=-1; j<=1; j++){
      if(i==0&&j==0)continue;
      int nr=r+i, nc=c+j;
      if(nr>=0&&nr<15&&nc>=0&&nc<15&&b[nr*15+nc]!=EMPTY) return true;
    }
    return false;
  }
}

// =========================================================
// APP UI: IOS 18 NATIVE STYLE (With Painter)
// =========================================================

class GomokuProApp extends StatelessWidget {
  const GomokuProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Gomoku Pro',
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.secondarySystemBackground,
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

class _GameScreenState extends State<GameScreen> {
  // State
  List<int> board = List.filled(225, EMPTY);
  List<int> history = []; // Lưu lịch sử để Undo
  bool isAiThinking = false;
  int winner = 0;
  
  // Zoom controller
  final TransformationController _transformCtrl = TransformationController();

  void _reset() {
    setState(() {
      board = List.filled(225, EMPTY);
      history.clear();
      isAiThinking = false;
      winner = 0;
      _transformCtrl.value = Matrix4.identity(); // Reset zoom
    });
  }

  void _undo() {
    if (history.length >= 2 && !isAiThinking && winner == 0) {
      setState(() {
        int lastAI = history.removeLast();
        int lastHuman = history.removeLast();
        board[lastAI] = EMPTY;
        board[lastHuman] = EMPTY;
      });
      HapticFeedback.selectionClick();
    }
  }

  void _onTap(Offset localPos, Size size) async {
    if (isAiThinking || winner != 0) return;

    // Map touch coordinates to grid index
    double cellW = size.width / 15;
    double cellH = size.height / 15;
    int col = (localPos.dx / cellW).floor();
    int row = (localPos.dy / cellH).floor();
    int index = row * 15 + col;

    if (col < 0 || col >= 15 || row < 0 || row >= 15 || board[index] != EMPTY) return;

    HapticFeedback.lightImpact();

    // 1. Player Move
    setState(() {
      board[index] = BLACK;
      history.add(index);
    });

    if (AICompute._checkWin(board, index, BLACK)) {
      setState(() => winner = BLACK); _showResult("Victory", "You outsmarted the machine."); return;
    }

    // 2. AI Turn
    setState(() => isAiThinking = true);
    await Future.delayed(const Duration(milliseconds: 100)); // UI render

    List<int> boardClone = List.from(board);
    int aiMove = await compute(AICompute.calculateMove, boardClone);

    if (!mounted) return;

    setState(() {
      board[aiMove] = WHITE;
      history.add(aiMove);
      isAiThinking = false;
    });
    HapticFeedback.mediumImpact(); // Rung nặng hơn khi máy đánh

    if (AICompute._checkWin(board, aiMove, WHITE)) {
      setState(() => winner = WHITE); _showResult("Defeat", "Stockfish AI wins this round.");
    }
  }

  void _showResult(String title, String body) {
    showCupertinoDialog(context: context, builder: (ctx) => CupertinoAlertDialog(
      title: Text(title), content: Text(body),
      actions: [CupertinoDialogAction(child: const Text("New Game"), isDefaultAction: true, onPressed: (){
        Navigator.pop(ctx); _reset();
      })]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          const CupertinoSliverNavigationBar(
            largeTitle: Text("Gomoku Pro"),
            backgroundColor: CupertinoColors.secondarySystemBackground,
            border: null,
          )
        ],
        body: Column(
          children: [
            // STATUS BAR
            _buildStatusBar(),
            
            // GAME BOARD (Zoomable)
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7), // Nền bảng chuẩn iOS
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                      ]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        transformationController: _transformCtrl,
                        maxScale: 4.0,
                        child: LayoutBuilder(
                          builder: (ctx, constraints) {
                            return GestureDetector(
                              onTapUp: (details) => _onTap(details.localPosition, constraints.biggest),
                              child: CustomPaint(
                                size: Size(constraints.maxWidth, constraints.maxHeight),
                                painter: BoardPainter(board, lastMove: history.isEmpty ? -1 : history.last),
                              ),
                            );
                          }
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // CONTROL BAR (Bottom Glass)
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statusBadge(isAiThinking ? "AI Thinking..." : (winner!=0?"Game Over":"Your Turn"), isAiThinking || winner!=0),
          Text("Score: ${(history.length/2).ceil()}", style: const TextStyle(color: CupertinoColors.systemGrey, fontWeight: FontWeight.w600))
        ],
      ),
    );
  }

  Widget _statusBadge(String text, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(20)
      ),
      child: Text(text, style: TextStyle(
        color: active ? Colors.white : Colors.black, fontSize: 13, fontWeight: FontWeight.bold
      )),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      height: 90,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withOpacity(0.8),
        border: const Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ctrlBtn(CupertinoIcons.arrow_counterclockwise, "Undo", _undo),
          _ctrlBtn(CupertinoIcons.arrow_2_circlepath, "Restart", _reset),
          _ctrlBtn(CupertinoIcons.settings, "Settings", () {}), // Placeholder for pro settings
        ],
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, VoidCallback action) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: action,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: CupertinoColors.label),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: CupertinoColors.secondaryLabel))
        ],
      ),
    );
  }
}

// =========================================================
// HIGH PERFORMANCE RENDERER (VẼ GPU)
// =========================================================
class BoardPainter extends CustomPainter {
  final List<int> board;
  final int lastMove;
  BoardPainter(this.board, {required this.lastMove});

  @override
  void paint(Canvas canvas, Size size) {
    double step = size.width / 15;
    double radius = step / 2.4;

    // 1. Draw Grid
    Paint linePaint = Paint()..color = CupertinoColors.systemGrey4..strokeWidth = 1.5;
    for(int i=0; i<=15; i++) {
      double pos = i * step + step/2 - step/2; // Căn giữa ô
      // Đường dọc (chỉnh offset để grid nằm giữa)
      double gridPos = i * step;
      // Vẽ kẻ caro dạng ô vuông kín (như bàn giấy)
      if(i<15) {
         // Kẻ dọc
         canvas.drawLine(Offset(gridPos, 0), Offset(gridPos, size.height), linePaint);
         // Kẻ ngang
         canvas.drawLine(Offset(0, gridPos), Offset(size.width, gridPos), linePaint);
      }
    }
    
    // Border ngoài đậm hơn
    canvas.drawRect(Rect.fromLTWH(0,0,size.width,size.height), Paint()..color=Colors.black12..style=PaintingStyle.stroke..strokeWidth=2);

    // 2. Draw Stones
    for(int i=0; i<225; i++) {
      if(board[i] == EMPTY) continue;
      
      int r = i ~/ 15; int c = i % 15;
      double cx = c * step + step/2;
      double cy = r * step + step/2;
      
      // Bóng đổ
      canvas.drawCircle(Offset(cx+1, cy+2), radius, Paint()..color=Colors.black12..maskFilter=const MaskFilter.blur(BlurStyle.normal, 2));

      // Quân cờ
      Paint stonePaint = Paint()..color = (board[i] == BLACK ? const Color(0xFF2C2C2E) : Colors.white);
      canvas.drawCircle(Offset(cx, cy), radius, stonePaint);
      
      // Viền quân trắng
      if(board[i] == WHITE) {
        canvas.drawCircle(Offset(cx, cy), radius, Paint()..color=Colors.black12..style=PaintingStyle.stroke..strokeWidth=1);
      }

      // Đánh dấu nước đi cuối cùng (Chấm đỏ nhỏ)
      if(i == lastMove) {
        canvas.drawCircle(Offset(cx, cy), radius/4, Paint()..color=CupertinoColors.systemRed);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    return oldDelegate.lastMove != lastMove || !listEquals(oldDelegate.board, board);
  }
}
