// 登录表单组件
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../transaction_service.dart';
class Global {
  static String? authentic_token;
}
// 登录表单组件
class LoginForm extends StatefulWidget {
  final Function(bool) onLoginChange; // 回调函数，用于通知父组件状态变化

  LoginForm({required this.onLoginChange});
  @override
  _LoginFormState createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  String username = '';
  String email = '';
  String password = '';
  TextEditingController usernameController = TextEditingController(text: "ZengLi");
  TextEditingController emailController = TextEditingController(text: "zengli@example.com");
  TextEditingController passwordController = TextEditingController(text: "string");
  bool isLoggedIn = false;

  void _toggleLogin() {
    setState(() {
      isLoggedIn = !isLoggedIn;
      widget.onLoginChange(isLoggedIn); // 将状态变化传递给父组件
    });
  }

  @override
  Widget build(BuildContext context) => Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15), // 圆角裁剪
        child: Container(
          width: 350, // 设置容器宽度
          padding: EdgeInsets.all(20), // 内边距
          decoration: BoxDecoration(
            color: Colors.white, // 背景颜色
            // 移除 borderRadius，因为我们已经在 ClipRRect 中裁剪了圆角
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min, // 使列的大小适应内容
              children: [
                Text(
                  '登录',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                // 用户名输入框
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => username = value!,
                ),
                SizedBox(height: 15),
                // 邮箱输入框
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: '邮箱',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => email = value!,
                ),
                SizedBox(height: 15),
                // 密码输入框
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  onSaved: (value) => password = value!,
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    _formKey.currentState!.save();
                    Global.authentic_token=await signin(username, email, password);
                    _toggleLogin();

                  },
                  child: Text('登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
}
