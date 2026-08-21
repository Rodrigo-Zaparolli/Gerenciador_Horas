import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegisterSuccess;

  const RegisterScreen({
    super.key,
    required this.onRegisterSuccess,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha todos os campos.',
              style: TextStyle(color: CoresApp.textoPrincipal)),
          backgroundColor: CoresApp.erro,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Cria o usuário no Firebase Auth
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Salva os dados extras (como o nome) no Cloud Firestore
      if (userCredential.user != null) {
        await userCredential.user?.updateDisplayName(name);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // 3. Desloga o usuário recém-criado para forçá-lo a fazer login manualmente
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Conta criada com sucesso! Faça login para continuar.',
                style: TextStyle(color: CoresApp.textoPrincipal)),
            backgroundColor: CoresApp.sucesso,
            duration: Duration(seconds: 4),
          ),
        );

        // Retorna para a tela de login
        widget.onRegisterSuccess();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Erro ao criar conta.';
      if (e.code == 'weak-password') {
        errorMessage =
            'A senha fornecida é muito fraca (mínimo de 6 caracteres).';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Já existe uma conta com este e-mail.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'O formato do e-mail é inválido.';
      } else {
        errorMessage = 'Erro (${e.code}): ${e.message ?? "Tente novamente."}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage,
                style: const TextStyle(color: CoresApp.textoPrincipal)),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Erro inesperado ao criar conta. Verifique sua conexão.',
                style: TextStyle(color: CoresApp.textoPrincipal)),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresApp.fundo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: CoresApp.primaria),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(36.0),
            decoration: BoxDecoration(
              color: CoresApp.superficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CoresApp.borda, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    height: 100,
                    width: 240,
                    child: Image.asset(
                      'assets/images/Logo_H.png',
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) {
                        return const Text(
                          'Gestão de Horas e Projetos',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Criar Nova Conta',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Preencha os dados abaixo para começar',
                  style:
                      TextStyle(color: CoresApp.textoSecundario, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Campo Nome
                TextField(
                  controller: _nameController,
                  style: const TextStyle(
                      color: CoresApp.textoPrincipal, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Nome completo',
                    labelStyle: const TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13),
                    prefixIcon: const Icon(Icons.person_outline,
                        color: CoresApp.primaria, size: 20),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: CoresApp.borda),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: CoresApp.primaria, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Campo E-mail
                TextField(
                  controller: _emailController,
                  style: const TextStyle(
                      color: CoresApp.textoPrincipal, fontSize: 14),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    labelStyle: const TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13),
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: CoresApp.primaria, size: 20),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: CoresApp.borda),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: CoresApp.primaria, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Campo Senha
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(
                      color: CoresApp.textoPrincipal, fontSize: 14),
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    labelStyle: const TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: CoresApp.primaria, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: CoresApp.textoFraco,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: CoresApp.borda),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: CoresApp.primaria, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Botão Cadastrar
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CoresApp.primaria,
                      foregroundColor: CoresApp.fundo,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CoresApp.fundo,
                            ),
                          )
                        : const Text(
                            'Cadastrar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
