//
//  ContentView.swift
//  Simigo
//
//  Created by 李杰 on 2025/10/31.
//

import SwiftUI

// 轻量入口视图，仅用于预览或占位，不再承载业务类型
struct ContentView: View {
    var body: some View {
        // 使用已拆分的视图作为主要内容
        MarketplaceView()
    }
}

#Preview {
    ContentView()
}
