import SwiftUI

/// Block layout is separate from inline Markdown so streamed headings and tables
/// keep their semantics instead of displaying Markdown punctuation verbatim.
struct AssistantMarkdown:View {
  let text:String
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      ForEach(Array(AssistantMarkdownBlock.parse(text).enumerated()),id:\.offset) {_,block in
        switch block {
        case .heading(let level,let title):
          inline(title).font(.system(size:level==1 ? 24:level==2 ? 20:17,weight:.semibold))
            .padding(.top,6).accessibilityAddTraits(.isHeader)
        case .paragraph(let value):inline(value).lineSpacing(6)
        case .item(let marker,let value):
          HStack(alignment:.top,spacing:8){Text(marker).foregroundStyle(.secondary);inline(value).frame(maxWidth:.infinity,alignment:.leading)}.lineSpacing(5)
        case .quote(let value):
          HStack(spacing:10){Rectangle().fill(.secondary.opacity(0.4)).frame(width:3);inline(value).foregroundStyle(.secondary)}.fixedSize(horizontal:false,vertical:true)
        case .code(let language,let value):
          VStack(alignment:.leading,spacing:8){
            if !language.isEmpty{Text(language).font(.system(size:10)).foregroundStyle(.secondary)}
            ScrollView(.horizontal){Text(verbatim:value).font(.system(size:12,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:true,vertical:false)}
          }.padding(12).background(.primary.opacity(0.055),in:RoundedRectangle(cornerRadius:10))
        case .table(let rows):table(rows)
        case .rule:Divider().opacity(0.45)
        }
      }
    }.font(.system(size:14)).textSelection(.enabled)
  }
  private func inline(_ value:String)->Text {
    Text((try? AttributedString(markdown:value,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
  }
  private func table(_ rows:[[String]])->some View {
    ScrollView(.horizontal) {
      Grid(alignment:.topLeading,horizontalSpacing:0,verticalSpacing:0) {
        ForEach(Array(rows.enumerated()),id:\.offset) {index,row in
          GridRow {
            ForEach(Array(row.enumerated()),id:\.offset) {_,cell in
              inline(cell).font(.system(size:13,weight:index==0 ? .semibold:.regular))
                .frame(minWidth:88,maxWidth:190,alignment:.leading).padding(10)
                .frame(maxHeight:.infinity,alignment:.topLeading)
                .background(.primary.opacity(index==0 ? 0.085:index.isMultiple(of:2) ? 0.025:0))
                .overlay(alignment:.bottom){Rectangle().fill(.secondary.opacity(0.18)).frame(height:0.5)}
            }
          }
        }
      }.fixedSize(horizontal:false,vertical:true)
    }.background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9)).clipShape(RoundedRectangle(cornerRadius:9))
  }
}

enum AssistantMarkdownBlock:Equatable {
  case heading(Int,String),paragraph(String),item(String,String),quote(String),code(String,String),table([[String]]),rule
  static func parse(_ text:String)->[Self] {
    let lines=text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
    var blocks:[Self]=[],index=0
    func cells(_ line:String)->[String] {
      var value=line.trimmingCharacters(in:.whitespaces)
      if value.hasPrefix("|"){value.removeFirst()};if value.hasSuffix("|"){value.removeLast()}
      // Escaped pipes belong to cells rather than table separators.
      return value.replacingOccurrences(of:"\\|",with:"\u{001F}").components(separatedBy:"|").map{$0.replacingOccurrences(of:"\u{001F}",with:"|").trimmingCharacters(in:.whitespaces)}
    }
    func delimiter(_ line:String)->Bool {
      let parts=cells(line)
      return !parts.isEmpty && parts.allSatisfy {cell in
        let clean=cell.replacingOccurrences(of:":",with:"").replacingOccurrences(of:" ",with:"")
        return clean.count>=3 && clean.allSatisfy{$0=="-"}
      }
    }
    func heading(_ line:String)->(Int,String)? {
      let count=line.prefix(while:{$0=="#"}).count
      guard (1...6).contains(count),line.count>count,line.dropFirst(count).first==" " else{return nil}
      return(count,String(line.dropFirst(count)).trimmingCharacters(in:.whitespaces))
    }
    func item(_ line:String)->(String,String)? {
      if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ "){return("•",String(line.dropFirst(2)))}
      let digits=line.prefix(while:{$0.isNumber})
      let tail=line.dropFirst(digits.count)
      if !digits.isEmpty,tail.hasPrefix(". ") || tail.hasPrefix(") "){return(String(digits)+".",String(tail.dropFirst(2)))}
      return nil
    }
    while index<lines.count {
      let line=lines[index].trimmingCharacters(in:.whitespaces)
      if line.isEmpty {index += 1;continue}
      if line.hasPrefix("```") || line.hasPrefix("~~~") {
        let fence=String(line.prefix(3)),language=String(line.dropFirst(3));index += 1
        var code:[String]=[]
        while index<lines.count,!lines[index].trimmingCharacters(in:.whitespaces).hasPrefix(fence){code.append(lines[index]);index += 1}
        blocks.append(.code(language,code.joined(separator:"\n")));if index<lines.count{index += 1};continue
      }
      if index+1<lines.count,line.contains("|"),delimiter(lines[index+1]) {
        var rows=[cells(line)];index += 2
        while index<lines.count,lines[index].contains("|"),!lines[index].trimmingCharacters(in:.whitespaces).isEmpty{rows.append(cells(lines[index]));index += 1}
        let count=rows[0].count
        rows=rows.map{Array(($0+Array(repeating:"",count:count)).prefix(count))}
        blocks.append(.table(rows));continue
      }
      if let (level,title)=heading(line){blocks.append(.heading(level,title));index += 1;continue}
      if ["---","***","___"].contains(line){blocks.append(.rule);index += 1;continue}
      if let (marker,value)=item(line){blocks.append(.item(marker,value));index += 1;continue}
      if line.hasPrefix("> "){blocks.append(.quote(String(line.dropFirst(2))));index += 1;continue}
      var paragraph=[line];index += 1
      while index<lines.count {
        let next=lines[index].trimmingCharacters(in:.whitespaces)
        if next.isEmpty || heading(next) != nil || item(next) != nil || next.hasPrefix("> ") || next.hasPrefix("```") || next.hasPrefix("~~~") || ["---","***","___"].contains(next) || (index+1<lines.count && next.contains("|") && delimiter(lines[index+1])){break}
        paragraph.append(next);index += 1
      }
      blocks.append(.paragraph(paragraph.joined(separator:"\n")))
    }
    return blocks
  }
}
