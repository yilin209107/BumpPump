import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AssistantPanel:View {
  @ObservedObject var agent:FitnessAgentState
  @ObservedObject var home:HomeState
  @ObservedObject var setup:SetupState
  var close:()->Void
  @Environment(\.appOpenSettings) private var openSettings
  @Environment(\.accessibilityReduceMotion) private var reduced
  @Environment(\.scenePhase) private var phase
  @Environment(\.appAnimationsVisible) private var animationsVisible
  @State private var composerHeight:CGFloat=20
  @State private var options=false
  @State private var attachmentOptions=false
  @AppPreference("assistant.shortcutsHintShown") private var shortcutsHintShown=false
  @State private var showingShortcutsHint=false
  private var palette:SetupPalette{setup.palette}
  var body:some View {
    ZStack(alignment:.leading) {
      Color(hex:setup.dark ? 0x242528:0xF1F0EE)
      AssistantSeamAurora(dark:setup.dark,reduced:reduced,active:phase == .active && animationsVisible).allowsHitTesting(false).accessibilityHidden(true)
      VStack(spacing:0) {
        HStack(spacing:12) {
          VStack(alignment:.leading,spacing:4) {
            Text("助理").font(.system(size:19,weight:.medium))
            Text(setup.recordingMode == .ai ? setup.provider.name+" · "+setup.model : "配置AI后开始对话").font(.system(size:10)).foregroundStyle(palette.secondary).lineLimit(1).truncationMode(.middle)
          }
          Spacer(minLength:4)
          Button{options.toggle()}label:{Image(systemName:"ellipsis").frame(width:26,height:26)}
            .modifier(AppGlassButton(circle:true)).disabled(agent.busy).accessibilityLabel("助理选项")
            .popover(isPresented:$options,arrowEdge:.bottom) {
              VStack(alignment:.leading,spacing:10) {
                Button("新对话",systemImage:"square.and.pencil"){options=false;agent.newConversation()}
                Menu("对话历史") {ForEach(agent.conversations.reversed()){conversation in Button(conversation.title){options=false;agent.select(conversation.id)}}}.menuStyle(.borderlessButton)
                Divider()
                Button("助理API设置…",systemImage:"slider.horizontal.3"){options=false;openAISettings()}
              }.buttonStyle(.borderless).padding(16).frame(width:220).onExitCommand{options=false}
            }
          Button(action:close){Image(systemName:"xmark").frame(width:26,height:26)}.modifier(AppGlassButton(circle:true)).foregroundStyle(palette.secondary).accessibilityLabel("收起助理")
        }.padding(.horizontal,22).padding(.top,12).padding(.bottom,14)
        ScrollViewReader {proxy in
            ScrollView {
              LazyVStack(alignment:.leading,spacing:22) {
                if agent.messages.isEmpty {
                  VStack(alignment:.leading,spacing:16) {
                    Image(systemName:"sparkle").font(.system(size:30,weight:.light)).foregroundStyle(palette.accent)
                    Text("今天，想记录些什么？").font(.system(size:26,weight:.medium)).tracking(-0.7)
                  }.padding(.top,62).padding(.bottom,36).frame(maxWidth:.infinity,alignment:.leading)
                }
                ForEach(AssistantTranscript.rows(agent.messages)) {row in
                  if let count=row.readCount {AssistantReadReceipt(count:count)}
                  else if let message=row.message {messageView(message)}
                }
                if agent.busy {HStack(spacing:8){ProgressView().controlSize(.mini);Text(agent.status).font(.system(size:11)).foregroundStyle(palette.secondary)}.padding(.vertical,8)}
                Color.clear.frame(height:1).id("assistant-bottom")
              }.padding(.horizontal,24)
            }.appDefaultScrollAnchor(.top)
              // The system reserves the composer's complete height for the final
              // scroll position. Unclipped content can still pass behind its glass.
              .appScrollClipDisabled()
              .safeAreaInset(edge:.bottom,spacing:0){bottomControls}
              .appOnChange(of:agent.messages.last?.text){_,text in if text != nil {proxy.scrollTo("assistant-bottom",anchor:.bottom)}}
              .appOnChange(of:agent.messages.count){_,count in if count > 0 {withAnimation(.easeOut(duration:reduced ? 0.05:0.18)){proxy.scrollTo("assistant-bottom",anchor:.bottom)}}}
          }
        .clipped()
      }
    }.foregroundStyle(palette.foreground).environment(\.usesGlassControls,true)
      .overlay(alignment:.leading){Rectangle().fill(palette.line.opacity(0.24)).frame(width:1)}
      .onAppear{
        setup.restoreSelection()
        if !shortcutsHintShown {showingShortcutsHint=true}
      }
      .alert("助理快捷键",isPresented:$showingShortcutsHint){
        Button("知道了"){shortcutsHintShown=true}
      }message:{Text("shift+enter发消息，enter为换行")}
  }
  @ViewBuilder private func messageView(_ message:AgentMessage)->some View {
    if message.role=="clock" {
      Label("已核对当前时间 · "+HomeFormat.date(message.date,pattern:"M月d日 HH:mm:ss"),systemImage:"clock")
        .font(.system(size:11)).foregroundStyle(palette.secondary)
    } else if message.role=="tool" {
      let json=(try? JSONSerialization.jsonObject(with:Data(message.text.utf8))) as? [String:Any]
      let ok=json?["ok"] as? Bool != false
      HStack(alignment:.top,spacing:7){Image(systemName:ok ? (message.toolName=="read_app_data" ? "magnifyingglass":"checkmark.circle") : "exclamationmark.circle");Text(ok ? (message.toolName=="read_app_data" ? "已查看本机记录":"已保存到本机") : (json?["error"] as? String ?? "操作未保存"))}.font(.system(size:11)).foregroundStyle(ok ? palette.secondary:palette.error).textSelection(.enabled)
    } else if message.role=="user" {
      VStack(alignment:.trailing,spacing:10){
        if !message.attachments.isEmpty {ForEach(message.attachments){file in Label(file.name,systemImage:file.isImage ? "photo":"doc.text").font(.system(size:11)).lineLimit(2).foregroundStyle(palette.secondary)}}
        if !message.text.isEmpty {Text(message.text).font(.system(size:14)).textSelection(.enabled).lineSpacing(5).padding(.horizontal,15).padding(.vertical,12).background(palette.secondary.opacity(0.10),in:RoundedRectangle(cornerRadius:18))}
      }.frame(maxWidth:.infinity,alignment:.trailing)
    } else if !message.text.isEmpty {
      VStack(alignment:.leading,spacing:8){
        AssistantMarkdown(text:message.text).frame(maxWidth:.infinity,alignment:.leading)
        if message.interrupted {Text("回复已中断").font(.system(size:10)).foregroundStyle(palette.secondary)}
      }
    }
  }
  private var bottomControls:some View {
    VStack(spacing:0) {
      if let error=agent.error {
        VStack(alignment:.leading,spacing:8) {
          Text(error).font(.system(size:12)).foregroundStyle(palette.error).textSelection(.enabled)
          if setup.recordingMode != .ai {Button("打开AI配置"){openAISettings()}.modifier(AppGlassButton())}
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,22).padding(.vertical,10)
      }
      composer.padding(.horizontal,18).padding(.top,14).padding(.bottom,16)
    }
  }
  private var composer:some View {
    VStack(alignment:.leading,spacing:10) {
      if !agent.attachments.isEmpty {
        ScrollView(.horizontal){HStack(spacing:8){ForEach(agent.attachments){file in
          HStack(spacing:6){Image(systemName:file.isImage ? "photo":"doc.text");Text(file.name).lineLimit(1);Button{agent.attachments.removeAll{$0.id==file.id}}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("移除附件"+file.name)}.font(.system(size:11)).padding(8).modifier(AppGlassSurface(radius:12))
        }}}
      }
      AppGlassGroup(spacing:10) {
        HStack(alignment:.center,spacing:10) {
          Button{attachmentOptions.toggle()}label:{Image(systemName:"plus").font(.system(size:19,weight:.medium)).frame(width:48,height:48).contentShape(Circle())}
            .modifier(AssistantComposerButton()).disabled(agent.busy || agent.attaching).accessibilityLabel("添加图片或文件").help("添加图片、PDF或文本文件")
            .popover(isPresented:$attachmentOptions,arrowEdge:.top) {
              VStack(alignment:.leading,spacing:10) {
                Button("选择文件",systemImage:"doc"){attachmentOptions=false;pick(imagesOnly:false)}
                Button("选择图片",systemImage:"photo"){attachmentOptions=false;pick(imagesOnly:true)}
              }.buttonStyle(.borderless).padding(16).frame(width:160).onExitCommand{attachmentOptions=false}
            }
          AssistantMessageEditor(text:$agent.draft,measuredHeight:$composerHeight,editable:!agent.busy,submit:send)
            .frame(height:composerHeight)
            .padding(.horizontal,16).padding(.vertical,14).frame(minHeight:48)
            .modifier(AppGlassSurface(radius:24))
          if agent.busy {
            Button{agent.cancel()}label:{Image(systemName:"stop.fill").font(.system(size:14)).frame(width:48,height:48).contentShape(Circle())}.modifier(AssistantComposerButton()).accessibilityLabel("停止回答和后续操作")
          }else{
            Button(action:send){Image(systemName:"arrow.up").font(.system(size:18,weight:.medium)).frame(width:48,height:48).contentShape(Circle())}.modifier(AssistantComposerButton(tint:palette.accent)).disabled(agent.attaching || (agent.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && agent.attachments.isEmpty)).accessibilityLabel("发送给助理")
          }
        }
      }
      if agent.attaching {
        HStack(spacing:6){ProgressView().controlSize(.mini);Text("正在准备附件…").font(.system(size:11)).foregroundStyle(palette.secondary)}
          .padding(.horizontal,3)
      }
    }
  }
  private func send(){
    guard !agent.busy,!agent.attaching,
          !agent.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !agent.attachments.isEmpty else{return}
    agent.send(home:home,setup:setup)
  }
  private func openAISettings(){UserDefaults.standard.set("ai",forKey:"BumpPump.settingsTab");openSettings()}
  private func pick(imagesOnly:Bool){
    let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=true;panel.allowedContentTypes=imagesOnly ? [.image]:[.pdf,.plainText,.json,.commaSeparatedText];panel.message="选择的附件会在发送消息时交给你配置的AI服务商。";panel.prompt="添加"
    panel.begin{response in if response == .OK {agent.addAttachments(panel.urls)}}
  }
}

struct AssistantSeamAurora:View {
  let dark:Bool
  let reduced:Bool
  let active:Bool
  private let colors:[Color]=[Color(hex:0x5D8CFF),Color(hex:0x45D4CF),Color(hex:0xA38AFA),Color(hex:0xF587AC),Color(hex:0xEFC477)]
  var body:some View {
    TimelineView(.animation(minimumInterval:1.0/30,paused:reduced || !active)){timeline in
      let time=reduced ? 0:timeline.date.timeIntervalSinceReferenceDate*0.72
      Canvas{context,size in
        context.addFilter(.blur(radius:34))
        for i in colors.indices {
          let phase=time+Double(i)*1.6
          let x=size.width*(0.04+sin(phase*0.6)*0.1),y=size.height*(Double(i)/4+sin(phase*0.8)*0.16)
          let radius=size.width*(0.6+cos(phase*0.9)*0.13)
          context.fill(Path(ellipseIn:CGRect(x:x-radius,y:y-radius*0.7,width:radius*2,height:radius*1.4)),with:.radialGradient(Gradient(colors:[colors[i].opacity(dark ? 0.43:0.26),.clear]),center:CGPoint(x:x,y:y),startRadius:0,endRadius:radius))
        }
      }.mask(LinearGradient(stops:[.init(color:.black,location:0),.init(color:.black.opacity(0.45),location:0.38),.init(color:.clear,location:1)],startPoint:.leading,endPoint:.trailing))
    }
  }
}

/// The 48-point frame belongs to each Button label so the whole glass circle
/// participates in pointer activation, rather than only the SF Symbol glyph.
private struct AssistantComposerButton:ViewModifier {
  var tint:Color?=nil
  @Environment(\.isEnabled) private var enabled
  @ViewBuilder func body(content:Content)->some View {
    if #available(macOS 26.0, *) {
      content.buttonStyle(.plain)
        .glassEffect(.regular.tint(enabled ? tint:nil).interactive(),in:Circle())
        .foregroundStyle(enabled ? Color.primary:Color.secondary)
    }else{
      content.modifier(AppGlassButton(circle:true)).frame(width:48,height:48)
    }
  }
}
