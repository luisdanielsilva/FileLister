import ftplib
import os
import getpass
import sys

def upload_dir(ftp, local_dir, remote_dir):
    try:
        ftp.cwd(remote_dir)
    except ftplib.error_perm:
        try:
            ftp.mkd(remote_dir)
            ftp.cwd(remote_dir)
        except Exception as e:
            print(f"Erro ao criar/entrar na pasta {remote_dir}: {e}")
            return

    for item in os.listdir(local_dir):
        # Ignore hidden files like .DS_Store
        if item.startswith('.'):
            continue
            
        local_path = os.path.join(local_dir, item)
        if os.path.isfile(local_path):
            print(f"A enviar ficheiro: {item}...")
            with open(local_path, 'rb') as f:
                ftp.storbinary(f'STOR {item}', f)
        elif os.path.isdir(local_path):
            print(f"A criar pasta: {item}...")
            upload_dir(ftp, local_path, item)
            ftp.cwd("..") # Go back up

def main():
    print("🚀 --- Deploy FTP do Single Use Apps --- 🚀\n")
    
    # Hardcoded host details from VistaPanel
    host = "ftpupload.net"
    user = "if0_41673076"
    remote_path = "htdocs"
    
    print(f"Host: {host}")
    print(f"Utilizador: {user}")
    print(f"Pasta Alvo: /{remote_path}\n")
    
    # getpass conceals the password while typing
    passwd = getpass.getpass("Coloca a Password do vPanel (não vai aparecer no ecrã): ")
        
    local_target = "webapp"
    
    if not os.path.exists(local_target):
        print(f"Erro: A pasta '{local_target}' não foi encontrada.")
        sys.exit(1)

    print("\nA ligar aos deuses do servidor FTP...")
    try:
        ftp = ftplib.FTP(host)
        ftp.login(user, passwd)
        print("✅ Ligação estabelecida com sucesso!")
        
        ftp.cwd(remote_path)
        print(f"Iniciando envio dos ficheiros locais de '{local_target}/' para '{remote_path}'...")
        
        # Upload contents of webapp folder recursively
        upload_dir(ftp, local_target, ".")
        
        ftp.quit()
        print("\n🎉 Deploy concluído! A tribo está na internet!")
    except Exception as e:
        print(f"\n❌ A ligação falhou ou ocorreu um erro: {e}")

if __name__ == "__main__":
    main()
