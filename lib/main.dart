import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const App());

// --- LOGIC TRÍ TUỆ NHÂN TẠO (AI) ---
class GomokuAI {
  static const int BOARD = 15;
  static const int EMPTY = 0;
  static const int BOT = 1;
  static const int HUMAN = 2;

  // Hàm tìm nước đi (Dùng Isolate để không lag máy)
  static int bestMove(List<int> board) {
    // 1. Nếu bàn cờ trống đánh vào giữa
    if (!board.contains(BOT) && !board.contains(HUMAN)) return 112;
    
    // 2. Kiểm tra sát cục (thắng ngay hoặc thua ngay)
    int win = _findWin(board, BOT); 
    if (win != -1) return win;
    int block = _findWin(board, HUMAN);
    if (block != -1) return block;

    // 3. Tính điểm các ô
    int best = -1;
    int maxScore = -999999;
    
    // Chỉ duyệt ô trống có hàng xóm (Cắt tỉa vùng thừa)
    for (int i = 0; i < 225; i++) {
      if (board[i] == EMPTY && _hasNeighbor(board, i)) {
        // Điểm tấn công + Điểm phòng thủ
        int score = _evaluate(board, i, BOT) + _evaluate(board, i, HUMAN);
        // Thêm chút ngẫu nhiên để không bị lặp nước
        score += Random().nextInt(5); 
        
        if (score > maxScore) {
          maxScore = score;
          best = i;
        }
      }
    }
    return best != -1 ? best : 112;
  }

  static int _findWin(List<int> b, int p) {
    for(int i=0; i<225; i++) {
      if(b[i] == EMPTY) {
        b[i] = p;
        if(checkWin(b, i, p)) { b[i] = EMPTY; return i; }
        b[i] = EMPTY;
      }
    }
    return -1;
  }

  static int _evaluate(List<int> b, int idx, int p) {
    int r = idx ~/ BOARD, c = idx % BOARD;
    int score = 0;
    // 4 hướng: Ngang, Dọc, Chéo 1, Chéo 2
    List<List<int>> dirs = [[1,0], [0,1], [1,1], [1,-1]];
    
    for (var d in dirs) {
      int count = 1, block = 0;
      // Duyệt chiều dương
      for(int k=1; k<5; k++) {
        int nr = r + d[1]*k, nc = c + d[0]*k;
        if(nr<0||nr>=BOARD||nc<0||nc>=BOARD) {block++; break;}
        if(b[nr*BOARD+nc] == p) count++;
        else if(b[nr*BOARD+nc] == EMPTY) break;
        else {block++; break;}
      }
      // Duyệt chiều âm
      for(int k=1; k<5; k++) {
        int nr = r - d[1]*k, nc = c - d[0]*k;
        if(nr<0||nr>=BOARD||nc<0||nc>=BOARD) {block++; break;}
        if(b[nr*BOARD+nc] == p) count++;
        else if(b[nr*BOARD+nc] == EMPTY) break;
        else {block++; break;}
      }
      
      if(block == 2) continue;
      if(count >= 5) score += 100000;
      else if(count == 4) score += 10000;
      else if(count == 3) score += 1000;
      else if(count == 2) score += 100;
    }
    return score;
  }

  static bool _hasNeighbor(List<int> b, int idx) {
    int r = idx ~/ BOARD, c = idx % BOARD;
    for(int i=-1; i<=1; i++) 
      for(int j=-1; j<=1; j++) {
         if (i==0 && j==0) continue;
         int nr=r+i, nc=c+j;
         if(nr>=0&&nr<BOARD&&nc>=0&&nc<BOARD&&b[nr*BOARD+nc]!=EMPTY) return true;
      }
    return false;
  }

  static bool checkWin(List<int> b, int idx, int p) {
     int r=idx~/BOARD, c=idx%BOARD;
     List<List<int>> dirs = [[1,0], [0,1], [1,1], [1,-1]];
     for(var d in dirs){
       int count=1;
       for(int k=1;k<5;k++){ // +
          int nr=r+d[1]*k, nc=c+d[0]*k;
          if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; count++;
       }
       for(int k=1;k<5;k++){ // -
          int nr=r-d[1]*k, nc=c-d[0]*k;
          if(nr<0||nr>=15||nc<0||nc>=15||b[nr*15+nc]!=p) break; count++;
       }
       if(count>=5) return true;
     }
     return false;
  }
}

// --- GIAO DIỆN (UI) ---
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(textTheme: GoogleFonts.poppinsTextTheme()),
    home: const Game(),
  );
}

class Game extends StatefulWidget {
  const Game({super.key});
  @override
  State<Game> createState() => _GameState();
}

class _GameState extends State<Game> {
  List<int> board = List.filled(225, 0);
  String msg = "Gomoku Stockfish Lite";
  bool thinking = false;

  void _tap(int i) async {
    if(board[i] != 0 || thinking || msg.contains("!")) return;

    // Người đánh
    setState(() { board[i] = GomokuAI.HUMAN; });
    if(GomokuAI.checkWin(board, i, GomokuAI.HUMAN)) {
      setState(() => msg = "YOU WIN!"); return;
    }

    // Máy đánh
    setState(() { thinking = true; msg = "Stockfish is thinking..."; });
    await Future.delayed(const Duration(milliseconds: 50)); // Render UI
    
    // Copy board sang isolate mới để tính toán
    List<int> clone = List.from(board);
    int aiMove = await compute(GomokuAI.bestMove, clone);
    
    setState(() {
      board[aiMove] = GomokuAI.BOT;
      thinking = false;
      msg = "Your Turn";
    });
    
    if(GomokuAI.checkWin(board, aiMove, GomokuAI.BOT)) {
      setState(() => msg = "GAME OVER!");
      _showReset();
    }
  }

  void _showReset() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Game Over"),
      content: const Text("Stockfish Won!"),
      actions: [TextButton(onPressed: (){
        Navigator.pop(c); setState((){board=List.filled(225,0); msg="Start";});
      }, child: const Text("Replay"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5e6ce),
      appBar: AppBar(title: const Text("Unsigned IPA Gomoku"), backgroundColor: Colors.brown),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(msg, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          if(thinking) const LinearProgressIndicator(),
          Expanded(child: Center(child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xffe3ac66), border: Border.all(width: 2)),
              child: GridView.builder(
                itemCount: 225,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 15),
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (c, i) => GestureDetector(
                  onTap: () => _tap(i),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
                    child: board[i]==0 ? null : Center(
                      child: Container(width: 16, height: 16, decoration: BoxDecoration(
                        shape: BoxShape.circle, color: board[i]==1?Colors.black:Colors.white,
                        boxShadow: const [BoxShadow(blurRadius: 2, offset: Offset(1,1))]
                      ))
                    )
                  ),
                )
              )
            )
          )))
        ],
      )
    );
  }
}
